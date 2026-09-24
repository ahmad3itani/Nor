"""01 LOWLIGHT: Security Station, the M7 world-skeleton stub (D0).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ll_security_station.py          # write world/rooms/lowlight/SecurityStation.tscn
    python3 -B tools/roomgen/ll_security_station.py --check  # exit 1 if the scene drifted

STUB: the final RoomGen line (bounds are final: the world map and the
overlap test use them), every door and entry spawn exactly as in the M7
door contracts (tests/unit/test_door_contracts.gd guards them), a 64x16
floor pad under each spawn so it lands on ground, and nothing else. Exits
carry no requires_flag yet: the room task adds each flag together with its
producer. Not playable end to end; use the dev console teleport.
The Security Station room task replaces this whole file with the real room.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import OUT

BOUNDS = (-64, -560, 1312, 800)
r = RoomGen("SecurityStation", BOUNDS, "lowlight", "Lowlight", "Security Station")


def pad(x, y):
    """64x16 floor pad centred under a spawn, clipped to the bounds."""
    x0, x1 = max(x - 32, BOUNDS[0]), min(x + 32, BOUNDS[0] + BOUNDS[2])
    r.block(x0, y, x1 - x0, 16)


# Entry spawns (id, x, y, facing): the door contracts.
r.spawn("from_power", 20, 0, 1, default=True)
pad(20, 0)
r.spawn("from_rainline", 1200, -384, -1)
pad(1200, -384)
# Doors (exit rect, target room, target entry).
r.exit(-64, -96, 16, 96, "PowerBlock", "from_security")
r.exit(1232, -480, 16, 96, "RainlineChase", "from_security")
r.write(OUT + "SecurityStation.tscn")

finish()
