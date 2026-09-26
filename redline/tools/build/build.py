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
--no-import, --gzip-web, --smoke, --check.

Python 3 standard library only, like tools/roomgen. No network: this script
and every tool under tools/ must not import a network module (rule PY-NET).
Needs the Godot 4.3.stable export templates for exports and --smoke only.

The invariants EX-1..EX-11 are the same list as
devtools/content/rules/ExportRules.gd (Python cannot call GDScript); keep the
two in step. tests/unit/test_export_presets.gd checks that both files name
the same rule ids.
"""
import argparse
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
NET_IMPORT_RE = re.compile(r"^\s*(?:import|from)\s+(urllib|http|socket|requests|ftplib)\b", re.M)
USER_DIRS = {
    "full": ("%APPDATA%\\Godot\\app_userdata\\REDLINE", "~/Library/Application Support/Godot/app_userdata/REDLINE",
             "~/.local/share/godot/app_userdata/REDLINE"),
    "demo": ("%APPDATA%\\REDLINE Demo", "~/Library/Application Support/REDLINE Demo", "~/.local/share/REDLINE Demo"),
}
BUDGET_WEB_GZ = 12 * 1024 * 1024
BUDGET_DESKTOP_ZIP = 40 * 1024 * 1024
BUDGET_MACOS_ZIP = 60 * 1024 * 1024  # universal: two architectures (measured 51-53 MB)


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
                for m in NET_IMPORT_RE.finditer(fh.read()):
                    errs.append("[PY-NET] %s imports %s (tools stay offline)" % (os.path.relpath(path, ROOT), m.group(1)))
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


def run_check():
    presets, project, gitignore = load_repo()
    errs = check_invariants(presets, project, gitignore) + check_no_network()
    for e in errs:
        print("DRIFT: " + e)
    if not errs:
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
        if gz_bytes > BUDGET_WEB_GZ:
            print("WARN: web gz payload %.1f MB > %.0f MB budget" % (gz_bytes / 1e6, BUDGET_WEB_GZ / 1e6))
    elif target != "web":
        budget = BUDGET_MACOS_ZIP if target == "macos" else BUDGET_DESKTOP_ZIP
        if artifacts[0]["bytes"] > budget:
            print("WARN: %s is %.1f MB > %.0f MB budget" % (name, artifacts[0]["bytes"] / 1e6, budget / 1e6))
    return artifacts, out_path


# --- Smoke (Linux exports only: the container can run those) -----------------------

def parse_build_info(stdout):
    for line in stdout.splitlines():
        if line.startswith("BUILD_INFO "):
            return json.loads(line[len("BUILD_INFO "):])
    return None


def smoke_problems(info, kind, debug):
    """What --smoke asserts about one BUILD_INFO record (also unit-testable)."""
    errs = []
    if info is None:
        return ["no BUILD_INFO line"]
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


def smoke(binary, kind, debug):
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, HOME=home, XDG_DATA_HOME=os.path.join(home, ".local", "share"))
        r = run([binary, "--headless", "--", "--print-build-info"], capture_output=True, text=True, env=env, timeout=300)
        info = parse_build_info(r.stdout)
        errs = smoke_problems(info, kind, debug)
        if r.returncode != 0:
            errs.append("exit code %d" % r.returncode)
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
    rc = 0
    if a.smoke:
        if not linux_bins:
            print("WARN: --smoke runs the Linux exports; add linux to --targets")
        for k, binary in linux_bins.items():
            probs = smoke(binary, k, a.debug)
            for p in probs:
                print("SMOKE FAIL (%s): %s" % (k, p))
            if probs:
                rc = 1
            else:
                print("SMOKE OK (%s)" % k)
    return rc


if __name__ == "__main__":
    sys.exit(main())
