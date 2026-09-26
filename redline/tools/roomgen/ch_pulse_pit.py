"""M9 challenge room: the Pulse Pit (D2 §2.3, §8.2), the arena for the two
Pulse Pit challenges (pit_style: fixed waves and a style score in 90 s;
pit_endurance: looping waves on the forced Challenge core until Rook falls).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ch_pulse_pit.py          # write world/rooms/challenge/PulsePit.tscn
    python3 -B tools/roomgen/ch_pulse_pit.py --check  # exit 1 if the scene drifted

One static screen (640 x 270, the camera frames the whole fight): a floor,
two one-way ledges (x 96..224 and 416..544 at y -72, one 48 px-safe jump
from the floor: 72 is reached from a run-jump's apex, and the ledges are only
perches), a Flow Zone over the whole pit (the Core drains, kills refill it),
the player spawn in the middle and six WaveSpawn markers: 1..4 on the floor
edges, 5 and 6 on the ledges. The WaveDirector runs whichever of the two
sets the live challenge names. Off the world map (ContentValidator
OFF_MAP_DIRS), no Anchor, no pickups, no exits: a run only ends by the
result card or a quit. Lowlight theme (placeholder art, D-026).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import BIG, RED, CYAN, AMBER

OUT = "world/rooms/challenge/"

p = RoomGen("PulsePit", (-64, -300, 768, 364), "lowlight", "Training Pit", "Pulse Pit", folder="challenge")

# --- Shell: one sealed screen ---
p.block(-64, -300, 768, 30, "Ceiling")          # underside -270
p.block(-64, -270, 64, 270, "WallLeft")
p.block(640, -270, 64, 270, "WallRight")
p.block(-64, 0, 768, BIG, "Floor")

# --- Perches (one-way: drop through with down + jump) ---
p.oneway(96, -72, 128)
p.oneway(416, -72, 128)

# --- The pit is one Flow Zone: standing still drains the Core ---
p.flow(0, -270, 640, 270)

p.spawn("start", 320, 0, 1, default=True)

# --- Wave spawns: 1..4 floor edges, 5..6 ledges (y is the feet, -2 like authored enemies) ---
p.wave_spawn(1, 40, -2)
p.wave_spawn(2, 136, -2)
p.wave_spawn(3, 504, -2)
p.wave_spawn(4, 600, -2)
p.wave_spawn(5, 160, -74)
p.wave_spawn(6, 480, -74)
p.wave_director(["pit_style", "pit_endurance"])

# --- Dressing: a training rig's lamps and stripes (visual only) ---
for x in [0, 628]:
    p.decor("pillar", x, 0, 12, 270, "0.16, 0.15, 0.2, 1")
p.neon(260, -250, 120, 14, RED, 6, False)
p.decor("pipes", 320, -2, 200, 2, AMBER)
p.neon(120, -120, 80, 10, CYAN, 3, False)
p.neon(440, -120, 80, 10, CYAN, 3, False)

p.write(OUT + "PulsePit.tscn")

finish()
