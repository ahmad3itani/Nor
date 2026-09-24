"""00 UNDERCITY: Broken Lift, the M7 world-skeleton stub (D0).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_broken_lift.py          # write world/rooms/undercity/BrokenLift.tscn
    python3 -B tools/roomgen/uc_broken_lift.py --check  # exit 1 if the scene drifted

STUB: the final RoomGen line (bounds are final: the world map and the
overlap test use them), every door and entry spawn exactly as in the M7
door contracts (tests/unit/test_door_contracts.gd guards them), a 64x16
floor pad under each spawn so it lands on ground, and nothing else. Exits
carry no requires_flag yet: the room task adds each flag together with its
producer. Not playable end to end; use the dev console teleport.
The Broken Lift room task replaces this whole file with the real room.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import OUT

BOUNDS = (-64, -800, 704, 896)
r = RoomGen("BrokenLift", BOUNDS, "undercity", "Undercity", "Broken Lift", max_attackers=1)


def pad(x, y):
    """64x16 floor pad centred under a spawn, clipped to the bounds."""
    x0, x1 = max(x - 32, BOUNDS[0]), min(x + 32, BOUNDS[0] + BOUNDS[2])
    r.block(x0, y, x1 - x0, 16)


# Entry spawns (id, x, y, facing): the door contracts.
r.spawn("from_pursuit", -20, 0, 1, default=True)
pad(-20, 0)
r.spawn("from_bay", 596, -576, -1)
pad(596, -576)
# Doors (exit rect, target room, target entry).
r.exit(-64, -96, 16, 96, "undercity/FirstPursuit", "from_lift")
r.exit(624, -672, 16, 96, "undercity/CollectorBay", "from_lift")
r.write(OUT + "BrokenLift.tscn")

finish()
