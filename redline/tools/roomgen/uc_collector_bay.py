"""00 UNDERCITY: Collector Bay, the M7 world-skeleton stub (D0).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_collector_bay.py          # write world/rooms/undercity/CollectorBay.tscn
    python3 -B tools/roomgen/uc_collector_bay.py --check  # exit 1 if the scene drifted

STUB: the final RoomGen line (bounds are final: the world map and the
overlap test use them), every door and entry spawn exactly as in the M7
door contracts (tests/unit/test_door_contracts.gd guards them), a 64x16
floor pad under each spawn so it lands on ground, and nothing else. Exits
carry no requires_flag yet: the room task adds each flag together with its
producer. Not playable end to end; use the dev console teleport.
The Collector Bay room task replaces this whole file with the real room.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import OUT

BOUNDS = (0, -240, 480, 270)
r = RoomGen("CollectorBay", BOUNDS, "undercity", "Undercity", "Collector Bay", max_attackers=1)


def pad(x, y):
    """64x16 floor pad centred under a spawn, clipped to the bounds."""
    x0, x1 = max(x - 32, BOUNDS[0]), min(x + 32, BOUNDS[0] + BOUNDS[2])
    r.block(x0, y, x1 - x0, 16)


# Entry spawns (id, x, y, facing): the door contracts.
r.spawn("from_lift", 28, 0, 1, default=True)
pad(28, 0)
r.spawn("from_tunnel", 436, 0, -1)
pad(436, 0)
# Doors (exit rect, target room, target entry).
r.exit(0, -96, 16, 96, "undercity/BrokenLift", "from_bay")
r.exit(464, -96, 16, 96, "undercity/EscapeTunnel", "from_bay")
# Stand-in producer until the room merges (the validator warns about it):
# collector_drone_defeated is set by the BossArena; orr_radio (D1), FirstPursuit, BrokenLift and way_up (D4) read it.
r.declare_flags("collector_drone_defeated")
r.write(OUT + "CollectorBay.tscn")

finish()
