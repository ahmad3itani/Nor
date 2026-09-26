"""M9 Deep Rig stratum N1 "Static Lane" (D3 §3.2 N1): movement grammar at
tempo, the first stage of a descent.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/null_static_lane.py          # write world/rooms/challenge/NullStaticLane.tscn
    python3 -B tools/roomgen/null_static_lane.py --check  # exit 1 if the scene drifted

Thesis: the Security Station's beam grammar and the Lowlight gaps, pulsed
and back to back, so the answer has to come at speed. Three sections:
- A Rhythm (x 0..700): pulsing beams 140 px apart (0.93 s at run speed):
  low 160, high 300 (phase 0.4), low 440 (phase 0.8), full 580. Jump,
  slide, jump, then dodge or wait (the calibration lane's shapes, pulsed:
  scanner_*_null.tres, on 0.8 s, off 0.8 s / 0.6 s for the full beam).
- B Gaps (x 700..1540): landings 700..820, 1020..1100, 1230..1330 and
  1530..: 200 (dash-jump), 130 (dodge-jump or a Dash), 200 (dash-jump). The
  pits are 48 px spike beds (a miss costs a pip; the 24 px ends are
  bare, so Rook always climbs out with one jump, never spirals). A steady
  high beam at 1580, right after the last landing, turns the landing into
  a slide (or a Dash, which blurs past it).
- C Flow fight (x 1700..2360): a Flow Zone at full drain over two Needles, a
  Scout Drone and a Watcher on a perch (the rig's tier: *_null data, no
  Scrap). Clearing is optional; the goal is open.
Goal (static_lane) at 2380, then the door to Breaker Run (a descent moves
on at the goal; the door is for dev teleports, exits are off in runs).
Every main-path step is <= 48 px. Pars are placeholders (D-154).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from null_style import BIG, OUT, THEME, DISTRICT, WHITE, GREY, RED

s = RoomGen("NullStaticLane", (-64, -360, 2560, 456), THEME, DISTRICT, "Static Lane", folder="challenge")

# --- Shell ---
s.block(-64, -360, 2560, 16, "Ceiling")
s.block(-64, -344, 16, 344, "WallLeft")
s.block(2480, -344, 16, 248, "WallRightUpper")      # the door below it (y -96..0)
s.block(-48, 0, 868, BIG, "FloorA")                 # x -48..820 (section A + the first landing)
s.block(1020, 0, 80, BIG, "LandingB1")
s.block(1230, 0, 100, BIG, "LandingB2")
s.block(1530, 0, 966, BIG, "FloorC")                # x 1530..2496

# --- Section B pits: 48 px spike beds, bare 24 px ends to climb out from ---
for x0, x1 in [(820, 1020), (1100, 1230), (1330, 1530)]:
    s.block(x0, 48, x1 - x0, 48)
    s.spikes(x0 + 24, 40, x1 - x0 - 48)

s.spawn("start", 20, 0, 1, default=True)

# --- A Rhythm: pulsing beams ---
s.scanner("nsl_low_1", 160, "low_null", top_y=-20, bottom_y=0)
s.scanner("nsl_high_1", 300, "high_null", top_y=-176, bottom_y=0, phase=0.4)
s.scanner("nsl_low_2", 440, "low_null", top_y=-20, bottom_y=0, phase=0.8)
s.scanner("nsl_full_1", 580, "full_null", top_y=-176, bottom_y=0)

# --- B: the landing slide under a steady high beam ---
s.scanner("nsl_high_2", 1580, "high", top_y=-176, bottom_y=0)

# --- C Flow fight (optional; the Core drains and kills refill it) ---
s.flow(1700, -300, 660, 300)
s.block(1860, -160, 80, 16, "WatcherPerch")
s.enemy("Watcher", 1900, -162)
s.enemy("Needle", 1760, -2, data="needle_null")
s.enemy("Needle", 2140, -2, data="needle_null")
s.enemy("ScoutDrone", 2040, -150, data="scout_drone_null")

# --- Goal and the door on to Breaker Run ---
s.goal(2380, -96, 40, 96, "static_lane")
s.neon(2380, -130, 40, 10, RED, 3, False)
s.exit(2480, -96, 16, 96, "NullBreakerRun", "from_lane")

# --- Dressing: white-grey rig frames (visual only) ---
for x in [-40, 690, 1520, 2470]:
    s.decor("pillar", x, 0, 10, 340, GREY)
s.decor("pipes", 350, -2, 700, 2, WHITE)
s.decor("pipes", 2030, -2, 660, 2, WHITE)

s.write(OUT + "NullStaticLane.tscn")

finish()
