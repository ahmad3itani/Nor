"""M7 M2 test fixtures (NPC objects, present_when, FlowZone drain tuning),
written with roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_props.py          # write tests/fixtures/props_*
    python3 -B tools/roomgen/fixtures_props.py --check  # exit 1 if the fixtures drifted

The NPC profiles live next to the scene (tests/fixtures/props_*.tres), not in
data/npcs: ContentValidator never scans tests/, so these throwaway profiles
cannot leak into the content pass. They are wired with raw() + _res() because
npc() only knows data/npcs/<profile>.tres and names nodes by profile.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roomgen
from roomgen import RoomGen, finish, q
from undercity_style import BIG

OUT = "tests/fixtures/"
RES = "res://" + OUT

# name -> (npc_id, display_name, map_label, figure, verb)
PROFILES = {
    "props_radio": ("props_radio", "Radio", "", False, "Listen"),
    "props_npc_x": ("props_npc_x", "Iko", "Scavenger", True, "Talk"),
    "props_npc_not_x": ("props_npc_not_x", "Iko Den", "Scavenger", True, "Talk"),
}


def profile_text(npc_id, name, label, figure, verb):
    out = ['[gd_resource type="Resource" script_class="NpcProfile" load_steps=2 format=3]', '',
           '[ext_resource type="Script" path="res://dialogue/NpcProfile.gd" id="1"]', '',
           '[resource]', 'script = ExtResource("1")', 'npc_id = %s' % q(npc_id), 'display_name = %s' % q(name)]
    if label: out.append('map_label = %s' % q(label))
    if not figure: out.append('figure = false')
    if verb != "Talk": out.append('verb = %s' % q(verb))
    return "\n".join(out) + "\n"


def write_text(path, text):
    """Same drift contract as RoomGen.write, for the profile resources."""
    if roomgen.CHECK:
        try:
            current = open(path).read()
        except OSError:
            current = None
        if current != text:
            roomgen._drift.append(path)
        return
    open(path, "w").write(text)


def npc(r, key, x, present_when=()):
    prof = r._res("npc_" + key, "Resource", RES + key + ".tres")
    p = ['position = Vector2(%d, 0)' % x, 'script = %s' % r._script("npc"), 'profile = %s' % prof, 'facing = -1']
    if present_when: p.append('present_when = %s' % roomgen.strings(present_when))
    r.raw("Interactables", "NPC_" + key, "Area2D", p)


def write_fixtures():
    for key, args in PROFILES.items():
        write_text(OUT + key + ".tres", profile_text(*args))
    # Flow A (scale 1.0, x 100..400) overlaps Flow B (scale 0.5, x 250..550):
    # stand at 175 for A alone, 325 for both, 475 for B alone. Flow C (scale
    # 0.5, floor 1) stands apart at 900..1100. NPCs sit between B and C.
    r = RoomGen("props_flow", (-64, -270, 1232, 400), "undercity", "Test", "Props flow")
    r.block(-48, 0, 1200, BIG, "Floor")
    r.spawn("start", 40, 0, 1, default=True)
    r.flow(100, -200, 300, 200)
    r.flow(250, -200, 300, 200, drain_scale=0.5)
    r.flow(900, -200, 200, 200, drain_scale=0.5, drain_floor=1.0)
    npc(r, "props_radio", 620)
    npc(r, "props_npc_x", 700, ("flag:x",))
    npc(r, "props_npc_not_x", 780, ("!flag:x",))
    r.write(OUT + "props_flow.tscn")


if __name__ == "__main__":
    write_fixtures()
    finish()
