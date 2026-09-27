#!/usr/bin/env python3
"""Env generation queue: lists owner=env manifest items still lacking a raw download,
in priority order, with the exact manifest prompt to pass to creative_generate_image
(model gpt-image-2, generations_count 1). Usage:
    python3 tools/assetgen/env_queue.py            # table of pending items
    python3 tools/assetgen/env_queue.py --json     # writes tools/assetgen/env_queue.json
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assetgen_paths import DATA  # noqa: E402
import env_process as ep  # noqa: E402
ROOT = DATA
m = json.load(open(os.path.join(ROOT, "art_manifest.json")))
env = sorted([a for a in m if a.get("owner") == "env"], key=lambda a: a["priority"])
pending = [a for a in env if a.get("source") != "code" and ep.raw_path(a["id"]) is None]
if "--json" in sys.argv:
    json.dump([{"id": a["id"], "priority": a["priority"], "model": "gpt-image-2",
                "est_generations": a.get("est_generations", 1),
                "prompt": a["generation_prompt"]} for a in pending],
              open(os.path.join(DATA, "env_queue.json"), "w"), indent=1)
for a in pending:
    print(a["priority"], a["id"], a.get("est_generations"), a.get("est_credits"))
print(len(pending), "pending,", sum(a.get("est_credits", 0) for a in pending), "est credits")
