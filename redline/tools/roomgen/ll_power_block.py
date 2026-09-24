"""01 LOWLIGHT: Power Block, the M7 world-skeleton stub (D0).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ll_power_block.py          # write world/rooms/lowlight/PowerBlock.tscn
    python3 -B tools/roomgen/ll_power_block.py --check  # exit 1 if the scene drifted

STUB: the final RoomGen line (bounds are final: the world map and the
overlap test use them), every door and entry spawn exactly as in the M7
door contracts (tests/unit/test_door_contracts.gd guards them), a 64x16
floor pad under each spawn so it lands on ground, and nothing else. Exits
carry no requires_flag yet: the room task adds each flag together with its
producer. Not playable end to end; use the dev console teleport.
The Power Block room task replaces this whole file with the real room.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import OUT

BOUNDS = (-64, -240, 1088, 1104)
r = RoomGen("PowerBlock", BOUNDS, "lowlight", "Lowlight", "Power Block")


def pad(x, y):
    """64x16 floor pad centred under a spawn, clipped to the bounds."""
    x0, x1 = max(x - 32, BOUNDS[0]), min(x + 32, BOUNDS[0] + BOUNDS[2])
    r.block(x0, y, x1 - x0, 16)


# Entry spawns (id, x, y, facing): the door contracts.
r.spawn("from_roofs", 20, 0, 1, default=True)
pad(20, 0)
r.spawn("from_smuggler", 20, 768, 1)
pad(20, 768)
r.spawn("from_security", 972, 768, -1)
pad(972, 768)
# Doors (exit rect, target room, target entry).
r.exit(-64, -96, 16, 96, "NeonRoofs", "from_power")
r.exit(-64, 672, 16, 96, "SmugglerRoute", "from_power")
r.exit(1008, 672, 16, 96, "SecurityStation", "from_power")
# Stand-in producer until the room merges (the validator warns about it):
# lowlight_power_rerouted is set by the basement lever; NeonRoofs' RainlineLive (D2b) and orr.tres (D4) read it.
r.declare_flags("lowlight_power_rerouted")
r.write(OUT + "PowerBlock.tscn")

finish()
