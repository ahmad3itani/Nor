#!/usr/bin/env python3
"""Env generation queue: lists owner=env manifest items still lacking a raw download,
in priority order, with the exact manifest prompt to pass to creative_generate_image
(model gpt-image-2, generations_count 1). Usage:
    python3 tools/assetgen/env_queue.py            # table of pending items
    python3 tools/assetgen/env_queue.py --json     # writes tools/assetgen/env_queue.json
    python3 tools/assetgen/env_queue.py --check    # env_queue.json is current (exit 1 if not)

T02: every entry carries `out`, the contract file names env_process.py writes for it. They
are the same files the code-painted layers (paint_env.py) ship today, so a generated raw
dropped into art/source/raw/<id>.png replaces the painted file with no code change.
`painted` names the builder that owns the file until then.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assetgen_paths import DATA  # noqa: E402
import env_process as ep  # noqa: E402
import paint_env as pe  # noqa: E402
ROOT = DATA
m = json.load(open(os.path.join(ROOT, "art_manifest.json")))
env = sorted([a for a in m if a.get("owner") == "env"], key=lambda a: a["priority"])
# painted items without a manifest entry (no AI prompt written yet)
EXTRA = [{"id": "uc_tunnel_mid", "priority": 2, "est_generations": 1,
          "generation_prompt": None, "note": "no manifest prompt yet: write one from ART_DIRECTION 4.1 "
          "(Escape Tunnel: ring ribs, trackbed, a dead two-car tram)"}]
PAINTED = {it["manifest"]: iid for iid, it in pe.ITEMS.items()}


def outs(i):
    if i in ep.RECIPES:
        r = ep.RECIPES[i]
        o = [r["out"]]
        if r.get("mode") == "swatch":
            o.append(r["out"].replace(".png", ".json"))
        return o
    if i in ep.SHEETS:
        s = ep.SHEETS[i]
        return [s["atlas"], s["atlas"].replace(".png", ".json")] if s.get("atlas") else [s["out"] + "/"]
    if i in PAINTED:
        return pe.outputs(PAINTED[i])
    return []


def entries():
    pending = [a for a in env + EXTRA if a.get("source") != "code" and ep.raw_path(a["id"]) is None]
    out = []
    for a in pending:
        e = {"id": a["id"], "priority": a["priority"], "model": "gpt-image-2",
             "est_generations": a.get("est_generations", 1), "prompt": a.get("generation_prompt"),
             "out": outs(a["id"]),
             "painted": ("paint_env.py " + PAINTED[a["id"]]) if a["id"] in PAINTED else None}
        if a.get("note"):
            e["note"] = a["note"]
        out.append(e)
    return out


def dump(q):
    return json.dumps(q, indent=1) + "\n"


if __name__ == "__main__":
    q = entries()
    path = os.path.join(DATA, "env_queue.json")
    if "--check" in sys.argv:
        ok = os.path.exists(path) and open(path).read() == dump(q)
        print("env_queue.json:", "current" if ok else "STALE (run env_queue.py --json)")
        sys.exit(0 if ok else 1)
    if "--json" in sys.argv:
        open(path, "w").write(dump(q))
    for a in q:
        print(a["priority"], a["id"], a["est_generations"], ",".join(a["out"]), a["painted"] or "")
    print(len(q), "pending,", sum(x.get("est_credits", 0) for x in env if x["id"] in {a["id"] for a in q}),
          "est credits")
