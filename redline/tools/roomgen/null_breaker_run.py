"""M9 Deep Rig stratum N2 "Breaker Run" (D3 §3.2 N2): routing under clocks,
the Grid thesis at the rig's tier.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/null_breaker_run.py          # write world/rooms/challenge/NullBreakerRun.tscn
    python3 -B tools/roomgen/null_breaker_run.py --check  # exit 1 if the scene drifted

Every shutter uses shutter_null.tres (open 3.1, warn 0.8, drop 0.2, slot
0.6, seal 0.15). test_null_routes.gd measures the margins of the intended
line (>= 0.35 s) and records them:
- nb_1 (floor breaker, x 100) opens NS1 at x 760. Running alone reaches it
  after the slot has sealed; the Dash in the line makes it standing. This
  is why the rig needs the Dash module (ChallengeData.requires).
- A lull: one Hopper after NS1, no clock.
- nb_2 (high breaker, box top -96 at x 860: a gun straight up or a jump and
  an air light) opens NS2 at x 1400; a Scout Drone hovers over the run (the
  bolt is dodged in the line, D3's Null-only exception).
- The expert line (optional, time only): floor -> one-way steps at -48 and
  -96 -> the ledge at -144 (1060..1180) -> a dash-jump (200 px: only a
  Dash spans it) onto NS2's housing (1380..1460, top -144) -> drop east.
  It skips nb_2.
- nb_3 (floor breaker, x 1700) opens NS3a (1860) and NS3b (1960) together,
  under a Flow Zone at 0.8 drain.
Goal (breaker_run) at 2120, then the door to The Floor. Every main-path
step is <= 48 px; shutter columns reach the floor, housings reach the
ceiling except NS2's (the expert line goes over it).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from null_style import BIG, OUT, THEME, DISTRICT, WHITE, GREY, RED

b = RoomGen("NullBreakerRun", (-64, -520, 2300, 616), THEME, DISTRICT, "Breaker Run", folder="challenge")

# --- Shell ---
b.block(-64, -520, 2300, 16, "Ceiling")
b.block(-64, -504, 16, 504, "WallLeft")
b.block(2220, -504, 16, 408, "WallRightUpper")      # the door below it (y -96..0)
b.block(-48, 0, 2268, BIG, "Floor")
b.spawn("from_lane", 20, 0, 1, default=True)

# --- NS1: the Dash clock ---
b.breaker("nb_1", "nb_c1", 100, -40)
b.shutter("NS1", 760, -96, 24, 96, "nb_c1", "shutter_null", "null_ns1_latched")
b.block(760, -504, 24, 408, "HousingNS1")

# --- The lull ---
b.enemy("Hopper", 1000, -2, data="hopper_null")

# --- NS2: the high breaker, the drone and the expert line over the housing ---
b.breaker("nb_2", "nb_c2", 860, -96)
b.shutter("NS2", 1400, -96, 24, 96, "nb_c2", "shutter_null", "null_ns2_latched")
b.block(1380, -144, 80, 48, "HousingNS2")
b.oneway(960, -48, 40)
b.oneway(1010, -96, 40)
b.oneway(1060, -144, 120)
b.enemy("ScoutDrone", 1250, -190, data="scout_drone_null")

# --- NS3a/b: one breaker, two shutters, under Flow pressure ---
b.flow(1500, -250, 600, 250, drain_scale=0.8)
b.breaker("nb_3", "nb_c3", 1700, -40)
b.shutter("NS3a", 1860, -96, 24, 96, "nb_c3", "shutter_null", "null_ns3a_latched")
b.block(1860, -504, 24, 408, "HousingNS3a")
b.shutter("NS3b", 1960, -96, 24, 96, "nb_c3", "shutter_null", "null_ns3b_latched")
b.block(1960, -504, 24, 408, "HousingNS3b")

# --- Goal and the door on to The Floor ---
b.goal(2120, -96, 40, 96, "breaker_run")
b.neon(2120, -130, 40, 10, RED, 3, False)
b.exit(2220, -96, 16, 96, "NullFloor", "from_breaker")

# --- Dressing (visual only) ---
for x in [40, 1320, 2210]:
    b.decor("pillar", x, 0, 10, 500, GREY)
b.decor("pipes", 430, -2, 600, 2, WHITE)
b.decor("pipes", 1800, -2, 600, 2, WHITE)

b.write(OUT + "NullBreakerRun.tscn")

finish()
