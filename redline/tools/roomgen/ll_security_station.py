"""01 LOWLIGHT: Security Station (M7), Krail's Lowlight outpost.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ll_security_station.py          # write world/rooms/lowlight/SecurityStation.tscn
    python3 -B tools/roomgen/ll_security_station.py --check  # exit 1 if the scene drifted

The Rainline platform sits on the station roof, so this is the only way
east. A Z-shaped interior: ground floor eastbound, upper floor westbound,
roof eastbound. Thesis (bible §41): scanner shapes one at a time
(calibration lane, zero damage), then live beams one at a time (lobby),
then pulsing beams, then breaker + searchlight on the roof (combining the
Power Block's Grid). Scanners are a support hazard only (D-072): 1 pip and
a knockback, never an alarm.

Level metrics (data/level/traversal_default.tres): run-jump reach 103 px,
jump rise 56 px, main-path steps <= 48 px. The stairwell hole is 80 px
(run-jumped); a fall there lands in the optional B1 isolation block, which
has 48 px climb-back steps. Beam windows are documented in ScannerBeam.gd
and measured by test_security.

Route tests: tests/unit/test_lowlight_m7_routes.gd (test_security_station_*,
test_ss_*). Change the layout here, regenerate, then re-run those tests.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import OUT, CYAN, RED

s = RoomGen("SecurityStation", (-64, -560, 1312, 800), "lowlight", "Lowlight", "Security Station")

# ---------------------------------------------------------------- shell
s.block(-64, -560, 16, 464, "WallLeft")
s.block(1232, -560, 16, 80, "WallRightTop")          # the roof door (y -480..-384) sits between these
s.block(1232, -384, 16, 624, "WallRight")
s.block(-48, 0, 648, 96, "GroundThick")
s.block(600, 0, 360, 16, "GroundThinA")
s.block(1040, 0, 192, 16, "GroundThinB")             # stairwell hole 960..1040 (80 px, run-jumped)
s.block(584, 16, 16, 128, "IsoWallW")
s.block(1040, 16, 16, 128, "IsoWallE")
s.block(584, 144, 648, 96, "IsoFloor")
s.block(360, -192, 740, 16, "UpperFloor")
s.block(360, -384, 872, 16, "RoofFloor")
# Cell block climb, ground -> upper floor (48 px steps).
for x, y in [(1116, -48), (1172, -96), (1116, -144)]:
    s.oneway(x, y, 56)
# Atrium climb, upper floor -> roof, west of the upper floor's edge (x 360).
for x, y in [(290, -240), (220, -288), (290, -336)]:
    s.oneway(x, y, 60)
# B1 climb-back to the ground floor; the overlap at x 990..1000 leaves a
# 40 px clearance so a standing Rook fits between the steps.
s.oneway(990, 48, 50)
s.oneway(960, 96, 40)

# ---------------------------------------------------------------- gatehouse calibration lane (x -48..360)
# Introduce with zero risk: live beams with damage 0 (a buzz, a flash,
# "TRIPPED" and a shove back), one hint area per shape so the verb appears
# on the shape it answers. Always live: it is the tutorial.
s.scanner("ss_cal_low", 100, "cal_low", top_y=-20, bottom_y=0)
s.block(198, -136, 28, 16, "CalHighHousing")
s.scanner("ss_cal_high", 210, "cal_high", top_y=-120, bottom_y=0)
s.block(310, -216, 24, 16, "CalFullHousing")
s.scanner("ss_cal_full", 320, "cal_full", top_y=-200, bottom_y=0)   # dodge is the only way past; retries are free

# ---------------------------------------------------------------- lobby (x 360..960)
# Reinforce, one live beam at a time: no enemies, no Flow. 220 / 240 px
# apart (1.5 s at run speed) so each beam is read and answered alone.
s.scanner("ss_low_1", 420, "low", top_y=-20, bottom_y=0)
s.scanner("ss_high_1", 640, "high", top_y=-176, bottom_y=0)
s.scanner("ss_full_1", 880, "full_pulse_14", top_y=-176, bottom_y=0)

# ---------------------------------------------------------------- cell block (x 1040..1232)
# The Shield and Drone reinforcement fight, in Flow (the Core drains while
# Rook lingers, hits refill it).
s.enemy("Shield", 1150, -2, -1)
s.enemy("ScoutDrone", 1120, -110)
s.flow(1040, -176, 192, 176)

# ---------------------------------------------------------------- upper floor "Monitor Corridor" (westbound)
# Guard post at the top of the climb, then the pulsing FULL and a HIGH 220 px
# on. No Watcher and no sweep here: the combination waits for the roof.
s.enemy("Needle", 1000, -194, -1)
s.enemy("Hopper", 900, -194, -1)
s.flow(860, -368, 240, 176)
s.scanner("ss_full_2", 760, "full_pulse_12", top_y=-368, bottom_y=-192)
s.scanner("ss_high_2", 540, "high", top_y=-368, bottom_y=-192)
# Landmark: the Monitor Wall (x 560..860, y -360..-230) with Rook's
# silhouette on the centre screen: the city authority is already watching
# him. Decor hangs from its bottom-centre, so y is the wall's bottom edge.
s.decor("banner", 710, -230, 300, 130, "0.12, 0.14, 0.18, 1", "0.9, 0.95, 1, 1")
s.decor("pillar", 710, -262, 10, 26, "0.85, 0.9, 0.95, 1")      # silhouette body
s.decor("pillar", 710, -290, 8, 8, "0.85, 0.9, 0.95, 1")        # silhouette head
for x in [420, 1040]:
    s.neon(x, -350, 10, 6, RED, 2)                                          # red strobes

# ---------------------------------------------------------------- roof (eastbound): combine
# Breaker + searchlight: strike the floor breaker, then run the 590 px under
# the dark searchlight. Attack 0.34 s + run 440 -> 1030 (3.93 s) = 4.27 s
# against the 5.5 s offline window (ScannerBeam defaults): a 1.23 s margin.
# Dodging through the live sweep is the skill alternative, never required.
# No roof enemies.
s.breaker("ss_roof", "ss_roof", 452, -424)
s.scanner("ss_searchlight", 620, "searchlight", top_y=-560, bottom_y=-384, circuit="ss_roof")
s.decor("pillar", 620, -384, 6, 176, "0.2, 0.2, 0.26, 1")      # emitter mast
s.neon(1170, -520, 60, 12, CYAN, 5, False)                      # "RAINLINE" over the roof door

# ---------------------------------------------------------------- B1 isolation (optional, hazard only)
# The stairwell fall. Two out-of-phase pulsing FULLs and a HIGH lead west to
# Cell Four; no enemies, no Flow. The climb-back steps are by the stairwell.
s.scanner("ss_b1_full_a", 920, "full_pulse_10", top_y=16, bottom_y=144)
s.scanner("ss_b1_full_b", 820, "full_pulse_10", top_y=16, bottom_y=144, phase=0.9)
s.scanner("ss_b1_high", 720, "high", top_y=16, bottom_y=144)
s.block(600, 16, 92, 48, "CellCeiling")
s.wall("ss_cell4_bars", 676, 64, 16, 80, 25, scrap=30)
s.collectible(1, "mf_lowlight_04", 630, 144, fragment="mf_lowlight_04")
s.collectible(0, "sb_ss_cell4", 655, 144, scrap=40)
s.decor("pipes", 760, 24, 300, 10, "0.3, 0.28, 0.3, 1")
s.decor("cables", 640, 72, 8, 14, "0.5, 0.5, 0.55, 1")         # tally marks on the cell wall

# ---------------------------------------------------------------- doors
s.spawn("from_power", 20, 0, 1, default=True)
s.spawn("from_rainline", 1200, -384, -1)
s.exit(-64, -96, 16, 96, "PowerBlock", "from_security")
s.exit(1232, -480, 16, 96, "RainlineChase", "from_security")

# ---------------------------------------------------------------- hints
# The calibration note and the first shape share one hint: from_power (x 20)
# sat inside a separate ss_calib box and ss_low fired 0.2 s later, replacing
# the only line that says this lane is harmless.
s.hint("ss_low", 50, -96, 40, 96, "Scanners on calibration: harmless. Low beam: jump it [{action}]", "jump")
s.hint("ss_high", 150, -96, 50, 96, "High beam: slide under [{action}]", "move_down")
s.hint("ss_full", 255, -96, 50, 96, "Full beam: dodge through it. Scanners read a dodge as a blur [{action}]", "dodge")
s.hint("ss_pulse", 760, -96, 60, 96, "It blinks. Wait for dark, or dodge.")
s.hint("ss_searchlight", 380, -480, 60, 96, "The searchlight runs off that breaker.")

# ---------------------------------------------------------------- world state
# After the Rainline chase the monitors lose Rook: static on every screen.
sl = s.switch("SignalLost", "flag:chase_rainline_done")
s.decor("banner", 710, -230, 300, 130, "0.3, 0.3, 0.32, 1", "0.6, 0.6, 0.6, 1", parent=sl)

s.write(OUT + "SecurityStation.tscn")
finish()
