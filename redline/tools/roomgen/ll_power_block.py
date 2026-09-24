"""01 LOWLIGHT: Power Block (M7). The district's Grid thesis room.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ll_power_block.py          # write world/rooms/lowlight/PowerBlock.tscn
    python3 -B tools/roomgen/ll_power_block.py --check  # exit 1 if the scene drifted

Rook descends a substation from roof level (L0, y 0) to the flooded
basement (L4, y 768) and reroutes the grid there: that sets
lowlight_power_rerouted, which puts the Security Station doors on priority
power (StationGate + the right basement exit), fails the grid locks open
(the Meter Room secret) and wakes the Rainline (NeonRoofs, Orr).

Thesis, one step per floor (breaker -> timed shutter, D-071):
  L0 introduce: a floor breaker beside a slow shutter (5.0 s for 90 px), safe.
  L1 the clock: the breaker sits 270 px from its shutter (1.06 s standing
     margin, the 24 px slot adds 0.85 s).
  L2 reach:     a high breaker (floor -96): jump-strike it or shoot straight up.
  L3 combine:   one breaker, two shutters and a duct slot between them, after a
     Flow Zone fight in the landing bay. The intended line slides under S4b.
Every ranged enemy can be fought before its floor's clock starts, and none
stands on a timed lane. Floors alternate direction; the four shafts carry
48 px one-way steps so every floor can be climbed back (shutters latch open
once crossed, so return trips are free and no drop can soft-lock).

Old saves (D-075) can arrive at from_security, west of StationGate: the
basement keeps the Anchor, the lever and the Smuggler exit reachable, and
shaft D leads only up to L3's west end, which unlatched S4b bounds.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import OUT, RED, CYAN, AMBER, VIOLET

REROUTED = "lowlight_power_rerouted"
CORE = "0.22, 0.18, 0.14, 1"        # the Transformer Core column
CABLE = "0.2, 0.2, 0.26, 1"
LAMP_POST = "0.2, 0.2, 0.26, 1"

p = RoomGen("PowerBlock", (-64, -240, 1088, 1104), "lowlight", "Lowlight", "Power Block")

# --- Shell, floors and shafts --------------------------------------------------------
p.block(-64, -240, 16, 144, "WallLeftTop")
p.block(-64, 0, 16, 672, "WallLeftMid")
p.block(1008, -240, 16, 912, "WallRight")
p.block(-48, -240, 1056, 40, "Ceiling")                     # underside -200
p.block(-48, 0, 928, 16, "L0")                              # shaft A x 880..1008
p.block(80, 192, 928, 16, "L1")                             # shaft B x -48..80
p.block(-48, 384, 448, 16, "L2a")
p.block(400, 432, 96, 16, "TrenchBottom")
p.spikes(400, 424, 96)
p.block(496, 384, 384, 16, "L2b")                           # shaft C x 880..1008
p.block(80, 576, 928, 16, "L3")                             # shaft D x -48..80
p.block(-48, 768, 1056, 96, "L4")                           # basement
# Shaft steps, 48 px apart: the way back up every shaft. Stacked steps that
# share an x are 96 px apart (88 px clearance, Rook is 34 tall).
for x, y in [(900, 144), (948, 96), (900, 48)]:
    p.oneway(x, y, 56)                                      # shaft A
for x, y in [(16, 336), (-40, 288), (16, 240)]:
    p.oneway(x, y, 56)                                      # shaft B
for x, y in [(900, 528), (948, 480), (900, 432)]:
    p.oneway(x, y, 56)                                      # shaft C
for x, y in [(16, 720), (-40, 672), (16, 624)]:
    p.oneway(x, y, 56)                                      # shaft D

# Landmark: the Transformer Core runs the full height (y -200..768), visible
# from every floor. Its arcs are red while the grid is on security priority
# and turn cyan after the reroute (the two switches below).
p.decor("pillar", 600, 768, 24, 968, CORE)
down = p.switch("GridDown", "!flag:" + REROUTED)
for y in [-120, 100, 300, 490, 680]:
    p.neon(606, y, 12, 6, RED, 2, True, parent=down)

# --- L0 (y 0): introduce. Safe; no Flow. ------------------------------------------
# Meter mezzanine: the Meter Room is seen locked from the first screen; the
# grid locks fail open after the reroute (the secret).
p.oneway(170, -48, 56)
p.oneway(230, -96, 70)
p.block(300, -96, 160, 16, "MeterFloor")
p.gate(300, -200, 16, 104, closed=True, open_flag=REROUTED, name="MeterGate")
p.block(444, -200, 16, 104, "MeterWallE")
p.wall("pb_meter_cabinet", 380, -192, 16, 96, 25, scrap=30)
p.collectible(0, "sb_pb_meter", 420, -96, scrap=40)
p.neon(330, -150, 18, 8, AMBER)                             # the meter dials behind the grid
# The first breaker stands right beside its shutter, 5.0 s for 90 px.
p.breaker("pb_b1", "pb_l0", 692, -40)                       # floor breaker
p.shutter("S1", 780, -200, 16, 200, "pb_l0", "shutter_intro", "pb_s1_latched")
p.decor("radio", 80, 0, 18, 14, "0.25, 0.22, 0.2, 1", AMBER)   # the grid-priority terminal
p.decor("pipes", 500, -170, 240, 12, CABLE)

# --- L1 (y 192), right to left: the clock -------------------------------------------
p.enemy("Needle", 700, 190, 1)                              # faces the shaft A landing; fought before the breaker
p.breaker("pb_b2", "pb_l1", 412, 152)
p.shutter("S2", 176, 16, 16, 176, "pb_l1", "shutter_run", "pb_s2_latched")
p.decor("crates", 300, 192, 26, 24, "0.26, 0.22, 0.18, 1")

# --- L2 (y 384), left to right: reach -----------------------------------------------
p.enemy("Hopper", 250, 382)                                 # a Hopper launched into the trench is an environmental kill
p.enemy("ScoutDrone", 620, 290)                             # hovers by B3; fought before the breaker
p.breaker("pb_b3", "pb_l2", 692, 288)                       # HIGH breaker: box top at floor -96
p.decor("cables", 700, 288, 8, 80, CABLE)                   # the box hangs from the L1 underside (y 208)
p.shutter("S3", 800, 208, 16, 176, "pb_l2", "shutter_run", "pb_s3_latched")

# --- L3 (y 576, ceiling 400), right to left: combine --------------------------------
# The landing bay fight happens inside a Flow Zone; the clock only starts at B4,
# east of the timed lane, so no drain runs during the shutter run.
p.flow(800, 400, 208, 176)
p.enemy("Needle", 840, 574, 1)                              # faces the shaft C landing
p.block(848, 496, 4, 16, "WatcherBracket")                  # bracket bottom 512: jump-strike or shoot the Watcher
p.decor("cables", 850, 496, 4, 96, CABLE)
p.enemy("Watcher", 850, 494, -1)
p.breaker("pb_b4", "pb_l3", 772, 536)
p.shutter("S4a", 700, 400, 16, 176, "pb_l3", "shutter_l3", "pb_s4a_latched")
p.block(520, 400, 48, 152, "Duct")                          # 48 px long, 24 px slot under it
p.shutter("S4b", 360, 400, 16, 176, "pb_l3", "shutter_l3", "pb_s4b_latched")

# --- L4 basement (y 768): breathing space. No Flow, no enemies. ------------------------
p.anchor("power_block", 420, 768)
p.lever(REROUTED, 880, 768, "Grid rerouted. Station doors on priority power. Overhead, the Rainline hums awake.")
p.gate(992, 672, 16, 96, closed=True, open_flag=REROUTED, name="StationGate")
p.neon(-20, 640, 20, 10, VIOLET, 3)                         # chalk eye: the smugglers' sign by their door
p.decor("workbench", 830, 768, 40, 18, "0.24, 0.2, 0.18, 1", RED)

# --- Doors ---------------------------------------------------------------------------
p.spawn("from_roofs", 20, 0, 1, default=True)
p.spawn("from_smuggler", 20, 768, 1)
p.spawn("from_security", 972, 768, -1)
p.exit(-64, -96, 16, 96, "NeonRoofs", "from_power")
p.exit(-64, 672, 16, 96, "SmugglerRoute", "from_power")
p.exit(1008, 672, 16, 96, "SecurityStation", "from_power", flag=REROUTED)

# --- Hints (one-shot) ----------------------------------------------------------------
p.hint("pb_terminal", 40, -96, 80, 96, "Security Station: grid-priority access only. Reroute at the basement relay.")
p.hint("pb_grid", 230, -200, 70, 104, "Sealed by the security grid.")
p.hint("pb_breaker", 600, -96, 80, 96, "Breakers power the shutters. Hit one [{action}]", "attack_light")
p.hint("pb_slot", 200, 96, 80, 96, "Shutter dropping? Get low and slide under [{action}]", "move_down")
p.hint("pb_reach", 620, 288, 80, 96, "Too high? Jump and strike it, or shoot straight up [{action}]", "ranged")

# --- World state: after the reroute the Core arcs run cyan and the basement lamps light.
g = p.switch("GridRerouted", "flag:" + REROUTED)
for y in [-120, 100, 300, 490, 680]:
    p.neon(606, y, 12, 6, CYAN, 2, False, parent=g)
for x in [240, 560, 760]:
    p.decor("lamp", x, 766, 6, 60, LAMP_POST, CYAN, parent=g)

p.write(OUT + "PowerBlock.tscn")
finish()
