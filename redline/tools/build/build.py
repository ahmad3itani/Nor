"""REDLINE release builds (M9 D6 §3.3, D-166): export the checked-in presets
(full + demo x Windows, Linux, macOS, Web) into deterministic zips plus a
manifest, with an invariant check that needs no Godot and a headless smoke
test of the Linux exports.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/build/build.py --check           # invariants only (no Godot); the gate runs this
    python3 -B tools/build/build.py                   # every preset, release
    python3 -B tools/build/build.py --targets linux --kinds full,demo --smoke
    python3 -B tools/build/build.py --targets web --kinds demo --gzip-web

Options: --godot PATH (else $GODOT, else `godot` on PATH), --targets
windows,linux,macos,web, --kinds full,demo, --debug (export-debug: the dev
console is ON in debug exports, K-42), --out DIR (default redline/build),
--no-import, --gzip-web, --smoke, --min-locales N (--smoke fails with fewer
locales; pass 2 once the .po files ship), --check.

Python 3 standard library only, like tools/roomgen. No network: this script
and every tool under tools/ must not import a network module (rule PY-NET).
Needs the Godot 4.3.stable export templates for exports and --smoke only.

The invariants EX-1..EX-11 are the same list as
devtools/content/rules/ExportRules.gd (Python cannot call GDScript); keep the
two in step. tests/unit/test_export_presets.gd checks that both files name
the same rule ids.
"""
import argparse
import ast
import fnmatch
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = os.path.join(ROOT, "tools")
HERE = os.path.dirname(os.path.abspath(__file__))

RULE_IDS = ["EX-1", "EX-2", "EX-3", "EX-4", "EX-5", "EX-6", "EX-7", "EX-8", "EX-9", "EX-10", "EX-11", "PY-NET"]
PLATFORMS = {"Windows": "Windows Desktop", "Linux": "Linux", "macOS": "macOS", "Web": "Web"}
TARGETS = {"windows": "Windows", "linux": "Linux", "macos": "macOS", "web": "Web"}
BINARIES = {"windows": "REDLINE.exe", "linux": "REDLINE.x86_64", "macos": "REDLINE.zip", "web": "index.html"}
REQUIRED_EXCLUDES = ["tests/*", "tools/*", "build/*"]
FORBIDDEN_EXCLUDES = ["devtools/*"]
REQUIRED_INCLUDES = ["data/challenges/ghosts/*.ghost", "locale/*.po"]
SECRET_KEY_RE = re.compile(r"password|keystore|identity|apple_id|team_id|api_?key|certificate|p12|provisioning", re.I)
# PY-NET: no network module in any Python tool (D-141, the user's local-only rule).
# Top-level module names; ast finds every name in "import os, socket", every
# "from x.y import z", and __import__("x") / importlib.import_module("x") calls,
# including aliases ("from importlib import import_module as im"; self_test).
NET_MODULES = {"urllib", "urllib2", "urllib3", "http", "socket", "socketserver", "ssl", "requests", "httpx",
               "aiohttp", "ftplib", "smtplib", "poplib", "imaplib", "telnetlib", "xmlrpc", "asyncio", "websocket",
               "websockets", "webbrowser"}


def net_imports(source, filename="<tool>"):
    """Banned top-level modules a Python source imports (PY-NET), in order."""
    found = []
    try:
        tree = ast.parse(source, filename)
    except SyntaxError as e:
        return ["<unparsable: %s>" % e.msg]
    # Every local name bound to a dynamic importer ("from importlib import
    # import_module as im", "from builtins import __import__ as imp").
    importers = {"__import__", "import_module"}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module in ("importlib", "builtins"):
            for a in node.names:
                if a.name in ("import_module", "__import__"):
                    importers.add(a.asname or a.name)
    for node in ast.walk(tree):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names = [node.module]
        elif isinstance(node, ast.Call):
            f = node.func
            fname = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else "")
            if fname in importers and node.args:
                arg = node.args[0]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    names = [arg.value]
                else:
                    names = ["<dynamic import>"]
        for n in names:
            top = n.split(".")[0]
            if top in NET_MODULES or n == "<dynamic import>":
                found.append(n)
    return found
USER_DIRS = {
    "full": ("%APPDATA%\\Godot\\app_userdata\\REDLINE", "~/Library/Application Support/Godot/app_userdata/REDLINE",
             "~/.local/share/godot/app_userdata/REDLINE"),
    "demo": ("%APPDATA%\\REDLINE Demo", "~/Library/Application Support/REDLINE Demo", "~/.local/share/REDLINE Demo"),
}
# Web gz payload budget (wasm + pck + js, gzip -9). Measured at T09 (overhaul):
# wasm 7.98 MB + js 0.09 MB are fixed; the full asset set made the pck 8.80 MB
# (16.86 MB in all). T09 shipped a partial web audio set (beds, mus_title,
# mus_undercity_explore): 13.55 MB full (over), 12.56 MB demo (20 KB left).
# The audit repair also leaves mus_title (0.98 MB) out of both web presets
# and the Lowlight beds (0.71 MB) out of the full one; the title and those
# rooms fall back to the synth stems / silence behind ResourceLoader.exists.
# An over-budget payload now FAILs the build (budget_verdict); measured
# numbers are in OVERHAUL_REPORT section 4 and D-180.
BUDGET_WEB_GZ = 12 * 1024 * 1024
BUDGET_DESKTOP_ZIP = 40 * 1024 * 1024
BUDGET_MACOS_ZIP = 60 * 1024 * 1024  # universal: two architectures (measured 53.4 MB)
# Less room than this under a budget WARNs (one more sheet or track would
# silently cross it).
BUDGET_HEADROOM = 500 * 1000


# --- Godot cfg reading (values are Godot literals, not INI-safe) ------------------

def parse_value(raw):
    raw = raw.strip()
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        return raw[1:-1].replace('\\"', '"')
    if raw in ("true", "false"):
        return raw == "true"
    try:
        return int(raw)
    except ValueError:
        try:
            return float(raw)
        except ValueError:
            return raw


def read_cfg(text):
    """{section: {key: value}} for a Godot cfg text (one-line values only)."""
    out, section = {}, None
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith(";") or s.startswith("#"):
            continue
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            out.setdefault(section, {})
        elif section is not None and "=" in s:
            k, v = s.split("=", 1)
            out[section][k.strip()] = parse_value(v)
    return out


def read_presets(text):
    cfg = read_cfg(text)
    presets = []
    for sec in cfg:
        if re.fullmatch(r"preset\.\d+", sec):
            p = dict(cfg[sec])
            p["options"] = cfg.get(sec + ".options", {})
            presets.append(p)
    return presets


def split_list(s):
    return [p.strip() for p in str(s).split(",") if p.strip()]


def numeric(version):
    m = re.match(r"(\d+\.\d+\.\d+)", version)
    return m.group(1) if m else version


# --- Invariants (EX-1..EX-11 as ExportRules.gd, plus PY-NET) --------------------

# EX-4 detail (overhaul T09, no new rule id: RULE_IDS stay in step with
# ExportRules.gd): an exclude_filter entry under assets/ may only drop
# optional files. Every file it matches must be referenced, if at all, as a
# plain string path by data or code whose loader guards it with
# ResourceLoader.exists (the MusicLibrary / ambience bed / backdrop /
# tileset paths), never by an ext_resource or a preload, so the build falls
# back (synth stems, silence, the procedural backdrop, flat tiles).
OPTIONAL_ASSET_PREFIX = "assets/"
# referrer (glob, relative to redline/) -> the runtime file whose loader guards its paths
GUARDED_REFERRERS = [
    ("data/audio/music/*.tres", "autoload/MusicDirector.gd"),
    ("data/audio/ambience/*.tres", "audio/AmbienceBank.gd"),
    ("data/presentation/backdrops/*.tres", "world/districts/PlaneSpec.gd"),
    ("data/districts/*.tres", "world/graybox/GrayboxBlock.gd"),
    ("world/districts/DistrictBackdrop.gd", "world/districts/DistrictBackdrop.gd"),
]
TEXT_EXTS = (".tres", ".tscn", ".gd", ".godot", ".cfg")
SCAN_SKIP = ("tests/", "tools/", "build/", ".godot/", "art/", "Docs/")
_repo_cache = {}


def repo_index(root=ROOT):
    """{"files": [rel paths], "texts": {rel: text}} of the project (cached)."""
    if root in _repo_cache:
        return _repo_cache[root]
    files, texts = [], {}
    for base, dirs, names in os.walk(root):
        rel_base = os.path.relpath(base, root).replace(os.sep, "/")
        rel_base = "" if rel_base == "." else rel_base + "/"
        dirs[:] = [d for d in dirs if not (rel_base + d + "/").startswith(SCAN_SKIP) and not d.startswith(".")]
        for f in names:
            rel = rel_base + f
            files.append(rel)
            if f.endswith(TEXT_EXTS):
                with open(os.path.join(base, f), encoding="utf-8", errors="replace") as fh:
                    texts[rel] = fh.read()
    _repo_cache[root] = {"files": sorted(files), "texts": texts}
    return _repo_cache[root]


def excluded_assets(excludes, files):
    """Files (no .import) that the assets/ entries of an exclude_filter drop."""
    pats = [x for x in excludes if x.startswith(OPTIONAL_ASSET_PREFIX)]
    return pats, [f for f in files if not f.endswith(".import") and any(fnmatch.fnmatchcase(f, p) for p in pats)]


def optional_asset_problems(preset, excludes, index=None):
    index = index or repo_index()
    files, texts = index["files"], index["texts"]
    pats, dropped = excluded_assets(excludes, files)
    errs = []
    for p in pats:
        if not any(fnmatch.fnmatchcase(f, p) for f in files):
            errs.append("[EX-4] '%s': exclude_filter %s matches no file" % (preset, p))
    dropped_set = set(dropped)
    for f in dropped:
        res = "res://" + f
        hard = re.compile(r'(ext_resource[^\n]*path="%s")|(preload\(\s*"%s")' % (re.escape(res), re.escape(res)))
        for ref, text in texts.items():
            if ref in dropped_set or res not in text:
                continue
            if hard.search(text):
                errs.append("[EX-4] '%s': excludes %s, but %s loads it as a hard reference" % (preset, f, ref))
                continue
            guard = next((g for glob, g in GUARDED_REFERRERS if fnmatch.fnmatchcase(ref, glob)), None)
            if guard is None:
                errs.append("[EX-4] '%s': excludes %s, but %s names it outside a guarded loader" % (preset, f, ref))
            elif "ResourceLoader.exists" not in texts.get(guard, ""):
                errs.append("[EX-4] '%s': excludes %s, but %s (the loader for %s) has no ResourceLoader.exists guard" % (preset, f, guard, ref))
    return errs


def payload_report(presets, root=ROOT, index=None):
    """One line per preset that drops optional assets: files and bytes."""
    index = index or repo_index(root)
    out = []
    for p in presets:
        _pats, dropped = excluded_assets(split_list(p.get("exclude_filter", "")), index["files"])
        if dropped:
            size = sum(os.path.getsize(os.path.join(root, f)) for f in dropped)
            out.append("EX-4 %s: leaves out %d optional asset files (%.2f MB; the runtime falls back)" % (
                p.get("name", "?"), len(dropped), size / 1e6))
    return out


def check_invariants(presets, project, gitignore):
    errs = []
    by_name = {}
    for p in presets:
        n = p.get("name", "")
        if n in by_name:
            errs.append("[EX-1] duplicate preset name '%s'" % n)
        by_name[n] = p
    expected = {}
    for base, plat in PLATFORMS.items():
        expected[base] = plat
        expected[base + " Demo"] = plat
    if len(presets) != len(expected):
        errs.append("[EX-1] %d presets, expected %d" % (len(presets), len(expected)))
    for n, plat in expected.items():
        if n not in by_name:
            errs.append("[EX-1] preset '%s' is missing" % n)
        elif by_name[n].get("platform") != plat:
            errs.append("[EX-1] preset '%s' platform is '%s', expected '%s'" % (n, by_name[n].get("platform"), plat))
    for n in by_name:
        if n not in expected:
            errs.append("[EX-1] unexpected preset '%s'" % n)
    app = project.get("application", {})
    version = numeric(str(app.get("config/version", "")))
    etc2 = project.get("rendering", {}).get("textures/vram_compression/import_etc2_astc", False) is True
    bundles = {}
    for n, p in by_name.items():
        o = p["options"]
        demo = n.endswith(" Demo")
        features = split_list(p.get("custom_features", ""))
        if demo != ("demo" in features):
            errs.append("[EX-2] '%s': custom_features must %scontain demo" % (n, "" if demo else "not "))
        for f in features:
            if f != "demo":
                errs.append("[EX-2] '%s': unexpected custom feature '%s'" % (n, f))
        if bool(p.get("runnable", False)) == demo:
            errs.append("[EX-3] '%s': runnable must be %s" % (n, "false" if demo else "true"))
        excludes = split_list(p.get("exclude_filter", ""))
        for x in REQUIRED_EXCLUDES:
            if x not in excludes:
                errs.append("[EX-4] '%s': exclude_filter lacks %s" % (n, x))
        for x in FORBIDDEN_EXCLUDES:
            if x in excludes:
                errs.append("[EX-4] '%s': exclude_filter must not exclude %s (runtime code lives there)" % (n, x))
        errs += optional_asset_problems(n, excludes)
        for k, v in o.items():
            if SECRET_KEY_RE.search(k) and isinstance(v, str) and v != "":
                errs.append("[EX-5] '%s': credential-like option %s has a value" % (n, k))
        if p.get("encrypt_pck", False):
            errs.append("[EX-5] '%s': encrypt_pck must be false (no key is ever stored)" % n)
        plat = p.get("platform")
        if plat == "Web":
            if o.get("variant/thread_support", True):
                errs.append("[EX-6] '%s': variant/thread_support must be false (nothreads)" % n)
            if o.get("progressive_web_app/enabled", True):
                errs.append("[EX-6] '%s': progressive_web_app/enabled must be false" % n)
        elif plat == "macOS":
            sv, vv = str(o.get("application/short_version", "")), str(o.get("application/version", ""))
            if sv != version or vv != version:
                errs.append("[EX-7] '%s': short_version '%s' / version '%s' must equal '%s' (config/version)" % (n, sv, vv, version))
            if o.get("binary_format/architecture") == "universal" and not etc2:
                errs.append("[EX-7] '%s': a universal macOS build needs import_etc2_astc=true in project.godot" % n)
            bundle = o.get("application/bundle_identifier", "")
            if bundle in bundles:
                errs.append("[EX-7] '%s': bundle id '%s' is also used by '%s'" % (n, bundle, bundles[bundle]))
            bundles[bundle] = n
        elif plat == "Windows Desktop":
            if o.get("application/modify_resources", True):
                errs.append("[EX-8] '%s': application/modify_resources must be false (no rcedit)" % n)
            if o.get("codesign/enable", True):
                errs.append("[EX-8] '%s': codesign/enable must be false" % n)
        includes = split_list(p.get("include_filter", ""))
        for x in REQUIRED_INCLUDES:
            if x not in includes:
                errs.append("[EX-11] '%s': include_filter lacks %s" % (n, x))
    if app.get("config/use_custom_user_dir.demo") is not True:
        errs.append("[EX-9] project.godot lacks config/use_custom_user_dir.demo=true")
    demo_dir = app.get("config/custom_user_dir_name.demo", "")
    if not demo_dir or demo_dir == app.get("config/custom_user_dir_name", ""):
        errs.append("[EX-9] project.godot config/custom_user_dir_name.demo must be set and differ from the base name")
    ignored = [l.strip() for l in gitignore.splitlines() if l.strip() and not l.strip().startswith("#")]
    if "export_presets.cfg" in ignored:
        errs.append("[EX-10] .gitignore must not list export_presets.cfg (it is checked in)")
    if "build/" not in ignored and "/build/" not in ignored:
        errs.append("[EX-10] .gitignore must list build/")
    return errs


def check_no_network(tools_dir=TOOLS):
    errs = []
    for base, _dirs, files in os.walk(tools_dir):
        if "__pycache__" in base:
            continue
        for f in sorted(files):
            if not f.endswith(".py"):
                continue
            path = os.path.join(base, f)
            with open(path, encoding="utf-8") as fh:
                for mod in net_imports(fh.read(), path):
                    errs.append("[PY-NET] %s imports %s (tools stay offline)" % (os.path.relpath(path, ROOT), mod))
    return errs


def refuse_secrets(presets):
    """Keys only, never values."""
    return [k for p in presets for k, v in p["options"].items() if SECRET_KEY_RE.search(k) and isinstance(v, str) and v]


def load_repo():
    def read(name):
        path = os.path.join(ROOT, name)
        return open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    presets = read_presets(read("export_presets.cfg"))
    project = read_cfg(read("project.godot"))
    return presets, project, read(".gitignore")


# Known sources and BUILD_INFO records --check runs the checkers against, so a
# regression in net_imports or smoke_problems fails the gate (review, T05).
SELF_TEST_NET = [
    ("import os, socket", ["socket"]),
    ("import json, urllib.request", ["urllib.request"]),
    ("from http import client", ["http"]),
    ("__import__('socket')", ["socket"]),
    ("import importlib\nimportlib.import_module('ssl')", ["ssl"]),
    ("from importlib import import_module as im\nim('socket')", ["socket"]),
    ("from builtins import __import__ as imp\nimp('requests')", ["requests"]),
    ("from importlib import import_module as im\nim(name)", ["<dynamic import>"]),
    ("import os, json, re\nimport importlib\nimportlib.import_module('json')", []),
]
SELF_TEST_SMOKE_OK = {"kind": "full", "locales": ["en", "ar"], "data": {"ghosts": 3},
                      "user_dir": "/home/x/.local/share/godot/app_userdata/REDLINE"}


def self_test():
    """Checker regressions, as DRIFT lines (empty when every case holds)."""
    errs = []
    for src, want in SELF_TEST_NET:
        got = net_imports(src)
        if got != want:
            errs.append("[SELF-TEST] net_imports(%r) = %s, expected %s" % (src, got, want))
    if smoke_problems(SELF_TEST_SMOKE_OK, "full", False, 2):
        errs.append("[SELF-TEST] smoke_problems rejects a good record: %s" % smoke_problems(SELF_TEST_SMOKE_OK, "full", False, 2))
    no_ghosts = dict(SELF_TEST_SMOKE_OK, data={})
    if not any("ghosts" in e for e in smoke_problems(no_ghosts, "full", False, 1)):
        errs.append("[SELF-TEST] smoke_problems accepts a record without a ghosts count")
    fake = {"files": ["assets/m/a.ogg", "assets/m/b.png", "data/audio/music/lib.tres", "autoload/MusicDirector.gd",
                      "ui/X.tscn"],
            "texts": {"data/audio/music/lib.tres": 'title = "res://assets/m/a.ogg"',
                      "autoload/MusicDirector.gd": "if ResourceLoader.exists(path):",
                      "ui/X.tscn": '[ext_resource type="Texture2D" path="res://assets/m/b.png" id="1"]'}}
    if optional_asset_problems("T", ["assets/m/a.*"], fake):
        errs.append("[SELF-TEST] EX-4 rejects a guarded string path: %s" % optional_asset_problems("T", ["assets/m/a.*"], fake))
    if not any("hard reference" in e for e in optional_asset_problems("T", ["assets/m/b.png"], fake)):
        errs.append("[SELF-TEST] EX-4 accepts excluding a hard-referenced asset")
    if not any("matches no file" in e for e in optional_asset_problems("T", ["assets/none/*"], fake)):
        errs.append("[SELF-TEST] EX-4 accepts a stale exclude pattern")
    one_locale = dict(SELF_TEST_SMOKE_OK, locales=["en"])
    if not any("locale" in e for e in smoke_problems(one_locale, "full", False, 2)):
        errs.append("[SELF-TEST] smoke_problems accepts 1 locale with --min-locales 2")
    return errs


def run_check():
    presets, project, gitignore = load_repo()
    errs = self_test() + check_invariants(presets, project, gitignore) + check_no_network()
    for e in errs:
        print("DRIFT: " + e)
    if not errs:
        for line in payload_report(presets):
            print(line)
        print("export presets OK (%d presets, EX-1..EX-11, PY-NET)" % len(presets))
    return 1 if errs else 0


# --- Building ---------------------------------------------------------------------

def godot_bin(arg):
    return arg or os.environ.get("GODOT") or shutil.which("godot") or "godot"


def run(cmd, **kw):
    print("$ " + " ".join('"%s"' % c if " " in c else c for c in cmd))
    return subprocess.run(cmd, **kw)


def godot_import(godot):
    r = run([godot, "--headless", "--path", ROOT, "--import"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("import failed (rc %d)" % r.returncode)


def export(godot, preset, out_path, debug):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)  # Godot refuses a missing folder (D6 §0.3)
    mode = "--export-debug" if debug else "--export-release"
    r = run([godot, "--headless", "--path", ROOT, mode, preset, out_path], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out_path):
        sys.stderr.write(r.stdout[-4000:] + r.stderr[-4000:])
        sys.exit("export '%s' failed (rc %d, output %s)" % (preset, r.returncode, "present" if os.path.exists(out_path) else "missing"))


def template(name, kind, version, label):
    text = open(os.path.join(HERE, name), encoding="utf-8").read()
    win, mac, lin = USER_DIRS[kind]
    return (text.replace("{version}", version).replace("{label}", label)
            .replace("{user_dir_windows}", win).replace("{user_dir_macos}", mac).replace("{user_dir_linux}", lin))


def zip_time():
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch:
        import time
        t = time.gmtime(max(int(epoch), 315532800))
        return (t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)
    return (1980, 1, 1, 0, 0, 0)


def _mode_for(name):
    if name.endswith(".x86_64") or name.endswith(".sh") or ".app/Contents/MacOS/" in name:
        return 0o755
    return 0o644


def zip_entries(entries, dst):
    """entries: [(arcname, bytes, external_attr or None)], written sorted and dated."""
    when = zip_time()
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for arc, data, attr in sorted(entries, key=lambda e: e[0]):
            info = zipfile.ZipInfo(arc, date_time=when)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = attr if attr is not None else ((0o100000 | _mode_for(arc)) << 16)
            z.writestr(info, data)


def dir_entries(src):
    out = []
    for base, _dirs, files in os.walk(src):
        for f in files:
            path = os.path.join(base, f)
            out.append((os.path.relpath(path, src).replace(os.sep, "/"), open(path, "rb").read(), None))
    return out


def gzip_bytes(data):
    return gzip.compress(data, compresslevel=9, mtime=0)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git_describe():
    try:
        r = subprocess.run(["git", "-C", ROOT, "describe", "--always", "--dirty"], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""
    except OSError:
        return ""


def build_one(godot, target, kind, version, debug, out_dir, gzip_web):
    preset = TARGETS[target] + (" Demo" if kind == "demo" else "")
    stage = os.path.join(out_dir, "stage", kind + ("_debug" if debug else ""), target)
    shutil.rmtree(stage, ignore_errors=True)
    out_path = os.path.join(stage, BINARIES[target])
    export(godot, preset, out_path, debug)
    label = version + (" DEMO" if kind == "demo" else "") + (" (debug)" if debug else "")
    how = template("HOW_TO_PLAY_%s.txt" % kind, kind, version, label).encode("utf-8")
    name = "REDLINE_%s%s%s_%s.zip" % (version, "_demo" if kind == "demo" else "", "_debug" if debug else "", target)
    dst = os.path.join(out_dir, name)
    if target == "macos":
        entries = []
        with zipfile.ZipFile(out_path) as src:
            for info in src.infolist():
                if not info.is_dir():
                    entries.append((info.filename, src.read(info), info.external_attr))
        entries.append(("HOW_TO_PLAY.txt", how, None))
    else:
        entries = dir_entries(stage)
        entries.append(("HOW_TO_PLAY.txt", how, None))
    if target == "web":
        entries.append(("SERVE_NOTES.txt", template("SERVE_NOTES.txt", kind, version, label).encode("utf-8"), None))
    zip_entries(entries, dst)
    artifacts = [{"file": name, "bytes": os.path.getsize(dst), "sha256": sha256(dst), "preset": preset,
                  "target": target, "kind": kind, "debug": debug}]
    if target == "web" and gzip_web:
        gz_dir = os.path.join(out_dir, "web%s_gz" % ("_demo" if kind == "demo" else ""))
        shutil.rmtree(gz_dir, ignore_errors=True)
        os.makedirs(gz_dir)
        for arc, data, _attr in dir_entries(stage):
            with open(os.path.join(gz_dir, arc), "wb") as fh:
                fh.write(data)
            if arc.rsplit(".", 1)[-1] in ("wasm", "pck", "js"):
                with open(os.path.join(gz_dir, arc + ".gz"), "wb") as fh:
                    fh.write(gzip_bytes(data))
        with open(os.path.join(gz_dir, "SERVE_NOTES.txt"), "w", encoding="utf-8") as fh:
            fh.write(template("SERVE_NOTES.txt", kind, version, label))
        gz_bytes = sum(os.path.getsize(os.path.join(gz_dir, f)) for f in os.listdir(gz_dir) if f.endswith(".gz"))
        artifacts[0]["web_gz_bytes"] = gz_bytes
        artifacts[0]["over_budget"] = budget_verdict("%s web gz payload" % kind, gz_bytes, BUDGET_WEB_GZ)
    elif target != "web":
        budget = BUDGET_MACOS_ZIP if target == "macos" else BUDGET_DESKTOP_ZIP
        artifacts[0]["over_budget"] = budget_verdict(name, artifacts[0]["bytes"], budget)
    return artifacts, out_path


def budget_verdict(what, size, budget):
    """Prints the size against its budget. Over budget is a build failure
    (main returns 1; never raise a budget silently, D-180); under
    BUDGET_HEADROOM of room left is a WARN so the next asset is noticed."""
    if size > budget:
        print("FAIL: %s %.2f MB > %.2f MB budget" % (what, size / 1e6, budget / 1e6))
        return True
    if budget - size < BUDGET_HEADROOM:
        print("WARN: %s %.2f MB is within %.2f MB of its %.2f MB budget" % (what, size / 1e6, BUDGET_HEADROOM / 1e6, budget / 1e6))
    else:
        print("%s %.2f MB (budget %.2f MB)" % (what, size / 1e6, budget / 1e6))
    return False


# --- Smoke (Linux exports only: the container can run those) -----------------------

def parse_build_info(stdout):
    for line in stdout.splitlines():
        if line.startswith("BUILD_INFO "):
            return json.loads(line[len("BUILD_INFO "):])
    return None


def smoke_problems(info, kind, debug, min_locales=1):
    """What --smoke asserts about one BUILD_INFO record (also unit-testable)."""
    errs = []
    if info is None:
        return ["no BUILD_INFO line"]
    locales = info.get("locales") or []
    if len(locales) < min_locales:
        errs.append("%d locale(s) %s, expected at least %d (include_filter locale/*.po)" % (len(locales), locales, min_locales))
    if "ghosts" not in (info.get("data") or {}):
        errs.append("BUILD_INFO data has no ghosts count (include_filter data/challenges/ghosts/*.ghost)")
    if info.get("kind") != kind:
        errs.append("kind is %s, expected %s" % (info.get("kind"), kind))
    if not debug and info.get("dev_console"):
        errs.append("the dev console is available in a release build")
    if kind == "demo" and info.get("demo", {}).get("relay_allowed", True):
        errs.append("the demo allows the Relay")
    user_dir = str(info.get("user_dir", "")).replace("\\", "/")
    if kind == "full" and not user_dir.endswith("app_userdata/REDLINE"):
        errs.append("full build user dir %s is not app_userdata/REDLINE" % user_dir)
    if kind == "demo" and not user_dir.endswith("/REDLINE Demo"):
        errs.append("demo user dir %s is not 'REDLINE Demo'" % user_dir)
    if info.get("problems"):
        errs.append("probe problems: %s" % info["problems"])
    return errs


def smoke(binary, kind, debug, min_locales=1):
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, HOME=home, XDG_DATA_HOME=os.path.join(home, ".local", "share"))
        r = run([binary, "--headless", "--", "--print-build-info"], capture_output=True, text=True, env=env, timeout=300)
        info = parse_build_info(r.stdout)
        errs = smoke_problems(info, kind, debug, min_locales)
        if r.returncode != 0:
            errs.append("exit code %d" % r.returncode)
        # A script that compiles in the editor can still fail in an export (a
        # resource load cycle the binary loader cannot resolve, M9 gate).
        script_errors = [l for l in (r.stdout + "\n" + r.stderr).splitlines() if "SCRIPT ERROR" in l]
        if script_errors:
            errs.append("%d SCRIPT ERROR line(s), first: %s" % (len(script_errors), script_errors[0].strip()))
        if info:
            print("  %s: version %s, locales %s, ghosts %s, data %s" % (kind, info.get("version"), info.get("locales"),
                  info.get("data", {}).get("ghosts"), info.get("data")))
        return errs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--godot")
    ap.add_argument("--targets", default="windows,linux,macos,web")
    ap.add_argument("--kinds", default="full,demo")
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--out", default=os.path.join(ROOT, "build"))
    ap.add_argument("--no-import", action="store_true")
    ap.add_argument("--gzip-web", action="store_true")
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--min-locales", type=int, default=1,
                    help="--smoke fails when a build lists fewer locales (2 once the .po files ship)")
    a = ap.parse_args(argv)
    if a.check:
        return run_check()
    targets, kinds = split_list(a.targets), split_list(a.kinds)
    for t in targets:
        if t not in TARGETS:
            sys.exit("unknown target %s (%s)" % (t, ", ".join(TARGETS)))
    for k in kinds:
        if k not in ("full", "demo"):
            sys.exit("unknown kind %s (full, demo)" % k)
    presets, project, gitignore = load_repo()
    errs = check_invariants(presets, project, gitignore) + check_no_network()
    secrets = refuse_secrets(presets)
    if errs or secrets:
        for e in errs:
            print("DRIFT: " + e)
        for k in secrets:
            print("SECRET: option %s has a value; credentials never go in export_presets.cfg" % k)
        return 1
    if a.debug:
        print("WARN: debug exports enable the dev console (K-42); never ship them")
    out_dir = os.path.abspath(a.out)
    os.makedirs(out_dir, exist_ok=True)
    open(os.path.join(out_dir, ".gdignore"), "a").close()  # Godot never imports its own outputs
    godot = godot_bin(a.godot)
    if not a.no_import:
        godot_import(godot)
    version = str(project.get("application", {}).get("config/version", "0"))
    artifacts, linux_bins = [], {}
    for t in targets:
        for k in kinds:
            arts, binary = build_one(godot, t, k, version, a.debug, out_dir, a.gzip_web)
            artifacts += arts
            if t == "linux":
                linux_bins[k] = binary
    manifest = {"version": version, "godot": "4.3.stable", "git": git_describe(), "artifacts": artifacts}
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
    for art in artifacts:
        print("%-44s %8.1f MB  %s" % (art["file"], art["bytes"] / 1e6, art["sha256"][:12]))
    over = [art["file"] for art in artifacts if art.get("over_budget")]
    rc = 0
    if over:
        print("FAIL: over budget: %s" % ", ".join(over))
        rc = 1
    if a.smoke:
        if not linux_bins:
            print("WARN: --smoke runs the Linux exports; add linux to --targets")
        for k, binary in linux_bins.items():
            probs = smoke(binary, k, a.debug, a.min_locales)
            for p in probs:
                print("SMOKE FAIL (%s): %s" % (k, p))
            if probs:
                rc = 1
            else:
                print("SMOKE OK (%s)" % k)
    return rc


if __name__ == "__main__":
    sys.exit(main())
