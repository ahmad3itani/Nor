"""00 UNDERCITY: Broken Lift (M7), the Core's safe introduction and the first Anchor.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_broken_lift.py          # write world/rooms/undercity/BrokenLift.tscn
    python3 -B tools/roomgen/uc_broken_lift.py --check  # exit 1 if the scene drifted

A vertical lift shaft (bible sec. 41 checklist):
- Entrance: the shaft foot, door at floor 0 (from First Pursuit).
- Movement: three zig-zag climbs of 48 px one-way steps (the main-path rise
  limit), and an optional 56 px drop from climb 2 onto the lift-car roof.
- Thesis: the Core, introduced safely (sec. 42, 15-30 min). FZ1 is the first
  Flow Zone: half drain and a floor of 1, so the Core drains while Rook
  lingers and a kill refills it, but it never empties or burns in any mode
  (D-070, D-085). Its first entry reveals the Core bar (core_hud_hidden) and
  shows the hostile-zone hint (hint_first_flow).
- Curiosity: 15 Scrap on the hanging lift car's roof, inside FZ1.
- Landmark: the lift car on its cables; its sodium sign lights after the
  Collector falls (collector_drone_defeated).
- Breathing space: Landing 2 (54 px above FZ1, no zone) and the Top Landing
  with the first Anchor, uc_lift, 124 px from the arena door (the Collector's
  checkpoint: a ~1.5 s runback).
- Exit: a sodium lamp by the arena door. No secrets (the car is curiosity).
One concept at a time: one Needle, max_attackers 1, only in FZ1.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import OUT, BIG, SODIUM, SEA, CONCRETE, RUST, STEEL

l = RoomGen("BrokenLift", (-64, -800, 704, 896), "undercity", "Undercity", "Broken Lift", max_attackers=1)

# ---------------------------------------------------------------- shell
l.block(-64, -800, 16, 704, "WallLeftUpper")      # left door y -96..0
l.block(-48, -800, 672, 40, "Ceiling")            # underside -760
l.block(624, -800, 16, 128, "WallRightTop")       # right door y -672..-576
l.block(624, -576, 16, 576, "WallRight")
l.block(-48, 0, 672, BIG, "Floor0")

# ---------------------------------------------------------------- climb 1 (no zone)
# Plain 48 px hops at the east wall: the player arrives rested, and climb 1
# stays outside FZ1 so the zone starts at a readable ledge (Landing 1).
for x, y in [(430, -48), (510, -96), (430, -144)]:
    l.oneway(x, y, 60)
l.block(-48, -192, 448, 16, "Landing1")           # x -48..400, top -192

# ---------------------------------------------------------------- climb 2 (lower half in FZ1)
for x, y in [(150, -240), (70, -288), (150, -336)]:
    l.oneway(x, y, 60)
# The car roof (x 250..330) hangs under Landing 2: a 56 px drop east from the
# -336 step, 54 px headroom under Landing 2's underside (-368). Walking off
# its east edge drops back to Landing 1, so a missed read costs only a climb.
l.block(250, -280, 80, 16, "LiftCarRoof")
l.collectible(0, "sb_uc_lift_car", 290, -280, scrap=15)
l.block(224, -384, 400, 16, "Landing2")           # x 224..624, safe (no zone)

# ---------------------------------------------------------------- climb 3 (safe)
for x, y in [(320, -432), (240, -480), (320, -528)]:
    l.oneway(x, y, 60)
l.block(380, -576, 244, 16, "TopLanding")         # x 380..624

# ---------------------------------------------------------------- the Core lesson
# FZ1 only: Landing 1 plus the lower climb 2 (y -330..-194). Rook on the top
# climb-2 step (-370..-336) and on Landing 2 is already outside. Half drain
# (Normal 2.5/s: a 20 s pace from 70 with one kill ends at 35 > critical 25)
# and a floor of 1: the heartbeat still plays when he idles, burnout never.
l.flow(-48, -330, 448, 136, drain_scale=0.5, drain_floor=1.0)
# The one fight of the room: a familiar Needle in the new Core context, so
# the player sees a kill refill the bar (bible sec. 42, 15-30 min).
l.enemy("Needle", 200, -194)

# ---------------------------------------------------------------- the first Anchor
l.anchor("uc_lift", 500, -576, -1)
# Reused lesson id (D-066): a new game learns Anchors here, and the Relay's
# copy stays silent for it.
l.hint("relay_anchor", 400, -672, 224, 96, "Anchors save, heal and refill. Rest to change your loadout.")

# ---------------------------------------------------------------- doors (door contracts)
l.spawn("from_pursuit", -20, 0, 1, default=True)
l.spawn("from_bay", 596, -576, -1)
l.exit(-64, -96, 16, 96, "undercity/FirstPursuit", "from_lift")
l.exit(624, -672, 16, 96, "undercity/CollectorBay", "from_lift")

# ---------------------------------------------------------------- set dressing
# The hanging lift car: its body under the roof, two cables to the ceiling
# (thin pillars read as taut cables; the 'cables' decor draws a sag).
l.decor("crates", 290, -220, 80, 60, RUST)
for x in (262, 318):
    l.decor("pillar", x, -280, 2, 480, STEEL)
# Shaft ribs and dead sea-green service tubes (ambience only, they flicker).
l.decor("pipes", 180, -40, 300, 12, CONCRETE)
l.decor("pipes", 470, -700, 260, 12, CONCRETE)
l.neon(40, -120, 24, 6, SEA, 1, True)
l.neon(560, -300, 24, 6, SEA, 1, True)
l.neon(60, -640, 24, 6, SEA, 1, True)
# Steady sodium marks the route only: one per climb and one by the exit.
for x, y in [(560, -60), (110, -250), (380, -460)]:
    l.neon(x, y, 8, 14, SODIUM, 1, False)
l.decor("lamp", 600, -576, 6, 64, STEEL, SODIUM)
l.neon(600, -640, 8, 14, SODIUM, 1, False)
# The landmark lights up once the Collector is down.
car = l.switch("CarLit", "flag:collector_drone_defeated")
l.neon(290, -300, 30, 6, SODIUM, 3, False, parent=car)

l.write(OUT + "BrokenLift.tscn")
finish()
