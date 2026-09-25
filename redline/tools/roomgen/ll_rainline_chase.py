"""01 LOWLIGHT: Rainline Chase, the district climax (M7).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ll_rainline_chase.py          # write world/rooms/lowlight/RainlineChase.tscn
    python3 -B tools/roomgen/ll_rainline_chase.py --check  # exit 1 if the scene drifted

Thesis: combine under pressure. Nothing new is taught here: run-jumps, the
gantry slides and the G3 slide-jump, while the Sweeper (a railcar hanging
from the overhead rail, ChaseDirector 'rainline', data/world/chase/
rainline.tres) hunts Rook east along the storm-lit elevated line toward the
Bell Tower. Failing costs little and never kills: a catch or a deck pit is
one nonlethal pip and a return to the last chase checkpoint; a G3 miss lands
on the LowRoad below the Sweeper's reach (about 1 s, no reset).

Deck and gap widths come from data/level/traversal_default.tres (run-jump
103 px, slide-jump 118 px, dodge-jump 149 px; 48 px steps):
    G1 800..872 (72)    G2 1040..1128 (88)    G3 1420..1532 (112, slide-jump)
    hatch 1700..1760 (60, over the LowRoad)   G4 3200..3296 (96)  G5 3496..3576 (80)
Gantries leave a 24 px slot, 48 px long (the duct rule: one slide clears it).
The car wells are 48 px deep and climbable; their Needles sit below the
car-to-car jump arcs and are optional launch targets. Tests:
tests/unit/test_lowlight_m7_routes.gd (test_rainline_*).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import OUT, BIG, RED, CYAN, AMBER

RAIL = "0.3, 0.3, 0.36, 1"
STEEL = "0.2, 0.2, 0.26, 1"
r = RoomGen("RainlineChase", (-64, -300, 4224, 500), "lowlight", "Lowlight", "Rainline")
r.block(-64, -300, 16, 204, "WallLeftUpper")
r.block(4144, -300, 16, 204, "WallRightUpper")
# Overhead rail at y -150 from x -48 to the buffer stop at 3560 (the
# Sweeper's derail_x in rainline.tres).
r.decor("cables", 1756, -150, 3616, 6, RAIL)

# --- The line ----------------------------------------------------------------------
r.block(-48, 0, 468, BIG, "Platform")
r.block(420, 0, 380, 16, "D1")                                  # G1 800..872 (72)
r.block(872, 0, 168, 16, "D2")                                  # G2 1040..1128 (88)
r.block(1128, 0, 292, 16, "D3")
r.block(1230, -176, 48, 152, "Gantry1")                         # 24 px slot, 48 px long
# G3 1420..1532 (112): the slide-jump under pressure. A miss lands on the
# LowRoad (y 72), below the Sweeper's catch rect (bottom at y -4), and climbs
# back up through the hatch gap: about a second lost, never a reset.
r.block(1420, 72, 340, 16, "LowRoad")
r.oneway(1706, 24, 48)
r.block(1532, 0, 168, 16, "D4")                                 # hatch gap 1700..1760 (60)
r.block(1760, 0, 440, 16, "D5")
r.block(1860, -176, 48, 152, "Gantry2")
r.block(2200, 0, 1000, 16, "D6")
# Parked cars on D6. Wells 2440..2520 and 2700..2760 are 48 deep.
r.block(2240, -48, 200, 48, "CarA")
r.block(2520, -48, 180, 48, "CarB")
r.block(2760, -96, 160, 96, "CarC")
# Coupler step (deviation from the plan): CarC's east face is 96 px above
# D6, higher than a jump, so without it the line would be one-way and a
# westbound player (Bell lift saves, the post-chase signal box) would be
# stuck. One-way, so eastbound runners drop straight through the arc.
r.oneway(2920, -48, 40)
# The high line: a greed route over the cars to the signal box (gap 130,
# a dodge-jump). Seen while running, meant for after the chase.
r.oneway(2270, -96, 40)
r.block(2320, -144, 100, 12, "HL1")
r.block(2550, -144, 140, 12, "HL2")
r.block(2610, -216, 80, 16, "BoxRoof")
# The box's back wall (deviation from the plan): without it CarC's roof
# reaches HL2 with a run-jump and walks around the breakable front.
r.block(2674, -200, 16, 56, "BoxBack")
r.wall("rc_signal_box", 2610, -200, 16, 56, 25, scrap=30)
r.collectible(0, "sb_rc_signal", 2660, -144, scrap=60)
# G4 3200..3296 (96)
r.block(3296, 0, 200, 16, "D8")                                 # G5 3496..3576 (80)
r.block(3576, 0, 568, BIG, "Terminal")

# --- Enemies: in the wells, below the jump arcs ------------------------------------
r.enemy("Needle", 2480, -2)
r.enemy("Needle", 2730, -2)

# --- Anchor, chase, doors ---------------------------------------------------------
# The Anchor sits before ChaseStart: a death re-arms after a 220 px walk.
r.anchor("rainline_platform", 200, 0)
r.chase("rainline", "rainline", path=[(60, 0), (1200, 0), (2000, 0), (2980, 0), (3620, 0)],
        speed_scale=[0.96, 0.8, 0.76, 1.0],                     # 120 / 100 / 95 / 125 px/s at base 125
        start_area=(420, -200, 16, 200), end_area=(3620, -200, 16, 200),
        checkpoints=[(440, 0), (1200, 0), (2000, 0), (2980, 0)])  # CP index 0..3 (index 0 = ChaseStart)
r.spawn("from_security", 20, 0, 1, default=True)
r.spawn("from_bell", 4100, 0, -1)
r.exit(-64, -96, 16, 96, "SecurityStation", "from_rainline")
r.exit(4144, -96, 16, 96, "BellTower", "from_rainline")

# --- Set dressing: a storm-lit elevated line, the Bell Tower on the horizon --------
# Trestle legs down to the street (the kill plane), clear of the pits' reads.
for x in [560, 960, 1300, 1840, 2320, 2640, 3060, 3400]:
    r.decor("pillar", x, 200, 14, 184, STEEL)
# Buffer stop at the rail's end, where the Sweeper tips off.
r.decor("pillar", 3560, 200, 10, 350, "0.26, 0.24, 0.28, 1")
r.neon(3560, -170, 14, 8, RED, 3, False)
r.decor("lamp", 240, 0, 6, 60, STEEL, AMBER)
r.decor("bench", 100, 0, 30, 12, "0.26, 0.22, 0.24, 1")
r.neon(200, -120, 60, 10, CYAN, 6, False)                       # RAINLINE platform sign
r.decor("lamp", 3700, 0, 6, 60, STEEL, AMBER)
r.decor("lamp", 3980, 0, 6, 60, STEEL, AMBER)
r.neon(4060, -140, 24, 10, AMBER)                               # signs the Bell Tower door
r.decor("ac", 2650, -216, 24, 16, STEEL, CYAN)                  # signal box aerial
r.neon(2650, -236, 12, 6, CYAN)
# After the chase: the Sweeper's wreck lies in the canal under the buffer
# stop (the parked car is simply never built once chase_rainline_done is set).
w = r.switch("SweeperWreck", "flag:chase_rainline_done")
r.decor("train", 3540, 196, 140, 40, "0.25, 0.1, 0.1, 1", parent=w)
# M8 map note (a rumour): Orr's line about the Rainline, at the chase start,
# from his line until the chase is run.
r.mapmarker(428, -100, "Orr: the Rainline is running again", "flag:chase_rainline_done", kind=2,
            shown_when="flag:orr_rainline_line")
r.write(OUT + "RainlineChase.tscn")

finish()
