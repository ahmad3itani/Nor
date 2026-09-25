"""Lowlight slice rooms, written with roomgen.

Run from redline/:
    python3 tools/roomgen/lowlight.py          # regenerate world/rooms/lowlight/*.tscn
    python3 tools/roomgen/lowlight.py --check  # exit 1 if the scenes differ from this script

The .tscn files are what the game loads. If you edit a room in the Godot
editor, either mirror the change here or stop regenerating that room
(--check tells you which rooms have drifted).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
OUT = "world/rooms/lowlight/"
RED, CYAN, AMBER, GREEN, VIOLET = "0.91, 0.16, 0.24, 1", "0.35, 0.88, 0.91, 1", "1, 0.81, 0.35, 1", "0.49, 1, 0.6, 1", "0.7, 0.45, 1, 1"
BIG = 96  # floor thickness

# ---------------------------------------------------------------- Relay (hub)
r = RoomGen("Relay", (-64, -360, 1100, 424), "relay", "The Relay", "Resistance hub")
r.block(-64, -360, 16, 424, "WallLeft")
r.block(-48, -360, 1100, 40, "Ceiling")
r.block(-48, 0, 1100, BIG, "Floor")
r.block(1008, -320, 32, 224, "WallRightUpper")
# "start" keeps its id (tests, CaptureTour, Game.START_ENTRY); since the
# Undercity opening it is the hub arrival point, not the New Game spawn.
r.spawn("start", 140, 0, 1, default=True, label="hub")
r.spawn("from_alley", 960, 0, -1)
r.spawn("from_lift", 16, 0, 1)
r.anchor("relay", 470, 0)
r.npc("orr", 220, 0, 1)
r.npc("mara", 660, 0, -1)
r.oneway(700, -40, 70)
r.oneway(760, -80, 150)
r.npc("vell", 850, -80, -1)
r.npc("nix", 330, 0, 1)
# Iko sets up her stall here after the first meeting in the Smuggler Route
# den (D-076). She stands on open floor at 580: her body and head (up to
# -37) would sit inside Vell's first step (700..770 at -40) further east.
# Her 24 px interact box (568..592) is clear of Mara (648..672) and the
# Anchor (470).
r.npc("iko", 580, 0, -1, present_when=["flag:met_iko"])
r.exit(1024, -96, 16, 96, "FloodedAlley", "from_relay")
r.gate(-32, -96, 16, 96, closed=True, open_flag="shortcut_bell_lift", name="LiftGate")
r.exit(-48, -96, 16, 96, "BellTower", "from_lift", flag="shortcut_bell_lift")
# Upper gallery door to the Undercity (M7): Rook climbs out of the Escape
# Tunnel onto this balcony, and any save can walk back down. Two one-way
# 48 px steps from the floor; the balcony underside (-128) stays clear of
# the LiftGate top (-96), so the lift door below is untouched.
r.block(-48, -144, 112, 16, "UndercityBalcony")
r.oneway(150, -48, 56)
r.oneway(84, -96, 56)
r.spawn("from_undercity", 0, -144, 1)
r.exit(-48, -240, 16, 96, "undercity/EscapeTunnel", "from_relay")
r.neon(470, -110, 40, 10, RED, 5, False)
r.neon(220, -80, 18, 8, CYAN)
r.neon(660, -90, 24, 8, AMBER)
r.neon(850, -150, 26, 8, GREEN)
r.neon(10, -262, 20, 8, VIOLET)  # signs the gallery door
r.hint("relay_talk", 100, -80, 80, 80, "Talk to Orr  [{action}]", "interact")
r.hint("relay_anchor", 420, -80, 100, 80, "Anchors save, heal and refill. Rest to change your loadout.")
# Set dressing: a dead transit interchange turned camp.
WARM = "0.32, 0.24, 0.2, 1"
for x in [80, 340, 600, 900]:
    r.decor("pillar", x, 0, 14, 320, "0.22, 0.17, 0.15, 1")
r.decor("train", 470, -118, 300, 60, "0.2, 0.16, 0.16, 1", "1, 0.75, 0.4, 1")
r.decor("cables", 470, -250, 520, 30, "0.4, 0.3, 0.25, 1")
for x in [150, 470, 720, 960]:
    r.decor("lamp", x, -2, 6, 60, "0.3, 0.24, 0.2, 1", "1, 0.72, 0.4, 1")
r.decor("radio", 250, 0, 18, 14, WARM, "0.35, 0.88, 0.91, 1")
r.decor("workbench", 610, 0, 40, 18, WARM, "0.91, 0.16, 0.24, 1")
r.decor("crates", 700, 0, 26, 26, "0.3, 0.22, 0.16, 1")
r.decor("bench", 400, 0, 30, 12, WARM)
r.decor("bench", 540, 0, 30, 12, WARM)
r.decor("banner", 330, -170, 26, 40, "0.35, 0.1, 0.13, 1", "1, 0.8, 0.7, 1")
r.decor("planter", 820, -80, 30, 16, WARM, "0.49, 0.8, 0.5, 1")
r.raw("Triggers", "SliceEnd", "Area2D", ['position = Vector2(380, -120)', 'script = ExtResource("slice_end")', 'size = Vector2(240, 120)'])
r.ext["slice_end"] = ("Script", "res://world/props/SliceEndTrigger.gd")
# The Relay evolves (bible §13): world-state switches keyed off progress.
radio = r.switch("RadioRestored", "flag:dead_air_complete")
r.neon(250, -140, 30, 10, CYAN, 6, False, parent=radio)
r.decor("cables", 250, -200, 8, 60, "0.4, 0.3, 0.25, 1", parent=radio)
for x in [120, 560, 840]:
    r.decor("lamp", x, -2, 6, 60, "0.3, 0.24, 0.2, 1", "1, 0.85, 0.55, 1", parent=radio)
trophy = r.switch("KrailTrophy", "flag:warden_krail_defeated")
r.decor("banner", 470, -200, 30, 50, "0.45, 0.08, 0.12, 1", "1, 0.81, 0.35, 1", parent=trophy)
r.neon(470, -225, 44, 8, RED, 4, False, parent=trophy)
charted = r.switch("NixCityMap", "flag:chart_lowlight_complete")
r.decor("banner", 360, -150, 60, 44, "0.16, 0.26, 0.24, 1", "0.49, 1, 0.6, 1", parent=charted)
r.write(OUT + "Relay.tscn")

# ---------------------------------------------------------------- Flooded Alley
a = RoomGen("FloodedAlley", (-64, -400, 1900, 496), "lowlight", "Lowlight", "Flooded Alley")
a.block(-64, -400, 16, 304, "WallLeftUpper")
a.block(-48, 0, 1880, BIG, "Floor")
a.block(1816, -400, 16, 304, "WallRightUpper")
a.spawn("from_relay", 24, 0, 1, default=True)
a.spawn("from_market", 1770, 0, -1)
a.exit(-64, -96, 16, 96, "Relay", "from_alley")
a.exit(1816, -96, 16, 96, "MarketRun", "from_alley")
# Dash-gated Core Shard, visible from the start (bible §5 ability-gated revisiting).
# A gap at one height cannot tell Dash from a late air dodge (the 220 px
# original leaked, and so would 234): the shelf drops 64 px across 290 px
# from a one-way take-off at -144, as in the Smuggler Route. A dash-jump from
# the lip crosses the shelf top at x ~455; the dodge-jump + air-dodge sweep
# finds no landing on it, even taken off 20 px late (282 px still leaked at
# 16 px late). From the -96 block under the take-off the same gap is only
# 16 px down. Air lights hang only when they connect (AttackData
# .air_velocity_on_hit, M7 D2b review): whiffed hangs let a floor jump +
# chained air lights reach this -80 top (peak ~-85) and a lip jump + lights
# glide past it; test_alley_dash_air_light_negative_sweep sweeps both.
a.oneway(40, -48, 50)
a.block(90, -96, 70, 16)
a.oneway(100, -144, 60)  # take-off, x 100..160 (jumped up through from the block)
a.block(450, -80, 56, 16, "DashShelf")
a.collectible(2, "cs_alley_dash", 468, -80)
a.mapmarker(300, -120, "Too wide to jump", "ability:dash")
a.hint("alley_gap", 60, -200, 100, 100, "Too far to jump. Maybe later.")
# Slide under the fence.
a.hint("alley_slide", 470, -96, 60, 96, "Run and hold [{action}] to slide", "move_down")
a.block(560, -160, 120, 136, "Fence")
# Hostile section.
a.flow(700, -300, 720, 300)
a.hint("alley_attack", 720, -96, 60, 96, "[{action}] attack", "attack_light")
a.hint("alley_dodge", 860, -96, 60, 96, "[{action}] dodge - it passes through attacks", "dodge")
a.enemy("Needle", 960, -2)
a.enemy("Needle", 1150, -2)
a.oneway(860, -56, 70)
# Building with a secret tunnel (Memory Fragment) and a roof route over it.
a.oneway(1220, -48, 60)
a.oneway(1250, -96, 50)
a.block(1300, -144, 120, 104, "BuildingTop")
a.block(1404, -40, 16, 40, "TunnelEnd")
a.wall("alley_tunnel_wall", 1300, -40, 16, 40, 20, scrap=40)
a.collectible(0, "sb_alley_tunnel", 1340, 0, scrap=40)
a.collectible(1, "mf_lowlight_01", 1368, 0, fragment="mf_lowlight_01")
a.neon(1360, -170, 34, 10, RED, 4)
for x in [300, 740, 1080, 1600]:
    a.decor("lamp", x, -2, 6, 70, "0.2, 0.2, 0.26, 1", "0.35, 0.88, 0.91, 1")
a.decor("crates", 230, 0, 28, 26, "0.2, 0.2, 0.25, 1")
a.decor("crates", 1500, 0, 30, 24, "0.2, 0.2, 0.25, 1")
a.decor("pipes", 900, -130, 400, 12, "0.22, 0.24, 0.3, 1")
a.decor("ac", 1330, -148, 18, 10, "0.26, 0.26, 0.32, 1")
a.decor("cables", 1000, -220, 600, 40, "0.18, 0.18, 0.24, 1")
a.neon(620, -190, 22, 8, CYAN)
a.neon(1000, -120, 26, 8, AMBER)
a.write(OUT + "FloodedAlley.tscn")

# ---------------------------------------------------------------- Market Run
m = RoomGen("MarketRun", (-64, -420, 2400, 516), "lowlight", "Lowlight", "Market Run")
m.block(-64, -420, 16, 324, "WallLeftUpper")
m.block(-48, 0, 1148, BIG, "FloorA")
m.block(1196, 0, 1140, BIG, "FloorB")
m.block(1100, 64, 96, 32, "PitBottom")
m.spikes(1100, 56, 96)
m.block(2320, -420, 16, 324, "WallRightUpper")
m.spawn("from_alley", 24, 0, 1, default=True)
m.spawn("from_stack", 2280, 0, -1)
m.exit(-64, -96, 16, 96, "FloodedAlley", "from_market")
m.exit(2320, -96, 16, 96, "ApartmentStack", "from_market")
m.flow(580, -320, 1440, 320)
m.hint("market_shoot", 420, -96, 60, 96, "[{action}] shoot - aim with the move keys", "ranged")
m.hint("market_launch", 980, -96, 60, 96, "Up + [{action}] launches enemies. Knock them into the spikes.", "attack_heavy")
for x, w in [(300, 80), (560, 80), (820, 90)]:
    m.oneway(x, -48, w)
m.oneway(600, -110, 100)
m.enemy("Hopper", 720, -2)
m.enemy("Needle", 960, -2)
m.enemy("Needle", 1320, -2)
m.enemy("Hopper", 1600, -2)
m.enemy("Needle", 1780, -2)
# Rooftop detour for the first repeater.
m.oneway(1290, -48, 60)
m.oneway(1340, -96, 60)
m.block(1400, -144, 160, 144, "MarketRoof")
m.repeater("repeater_market", 1500, -144)
# Secret stash in the last building: roof route over, cracked wall under.
m.oneway(1930, -48, 50)
m.block(2000, -96, 140, 56, "StashRoof")
m.wall("market_stash_wall", 2000, -40, 16, 40, 25, scrap=60)
m.block(2124, -40, 16, 40, "StashBack")
m.collectible(2, "cs_market", 2070, 0)
for x in [150, 450, 1000, 1700, 2250]:
    m.decor("lamp", x, -2, 6, 64, "0.2, 0.2, 0.26, 1", "1, 0.81, 0.35, 1")
for x in [340, 600, 860]:
    m.decor("crates", x + 20, 0, 26, 22, "0.25, 0.2, 0.2, 1")
m.decor("ac", 1450, -144, 20, 12, "0.26, 0.26, 0.32, 1")
m.decor("cables", 700, -200, 700, 40, "0.18, 0.18, 0.24, 1")
for x, c in [(340, RED), (600, CYAN), (860, AMBER), (1480, GREEN), (2070, RED)]:
    m.neon(x, -80 if x < 1400 else -190, 30, 8, c)
m.write(OUT + "MarketRun.tscn")

# ---------------------------------------------------------------- Apartment Stack (vertical)
# Floors every 192 px; three 48 px steps per climb, zigzagging inside the hole.
s = RoomGen("ApartmentStack", (-64, -960, 704, 1056), "lowlight", "Lowlight", "Apartment Stack")
s.block(-64, -960, 16, 864, "WallLeft")
s.block(624, -960, 16, 96, "WallRightTop")
# Ground-floor hatch to the Smuggler Route (M7 optional loop): bolted from
# the tunnel side until the den lever there sets shortcut_smuggler_route, so
# the loop is only ever opened from the Smuggler Route (D2b).
s.block(624, -768, 16, 672, "WallRight")
s.block(-48, 0, 672, BIG, "Floor0")
s.spawn("from_market", 20, 0, 1, default=True)
s.spawn("from_roofs", 580, -768, -1)
s.spawn("from_smuggler", 580, 0, -1)
s.exit(-64, -96, 16, 96, "MarketRun", "from_stack")
s.exit(624, -864, 16, 96, "NeonRoofs", "from_stack")
s.exit(624, -96, 16, 96, "SmugglerRoute", "from_stack", flag="shortcut_smuggler_route")
s.gate(608, -96, 16, 96, closed=True, open_flag="shortcut_smuggler_route", name="HatchGate")
# Silent once unbolted: Rook then arrives through this hatch (from_smuggler
# sits inside the hint box) and the line would be false.
s.hint("stack_hatch", 540, -96, 60, 96, "Bolted from the other side.", skip_when="flag:shortcut_smuggler_route")
s.mapmarker(600, -60, "Hatch: bolted from the tunnel side", "flag:shortcut_smuggler_route")
s.neon(600, -130, 20, 8, VIOLET)  # the smugglers' chalk eye
s.hint("stack_heal", 60, -96, 80, 96, "Hurt? Stand still and hold on: [{action}] uses an injector", "heal")
def climb_right(room, y0):
    for x, dy in [(430, 48), (510, 96), (430, 144)]:
        room.oneway(x, y0 - dy, 60)
def climb_left(room, y0):
    for x, dy in [(150, 48), (70, 96), (150, 144)]:
        room.oneway(x, y0 - dy, 60)
# Floor 1 (-192), hole right, repeater room on the left.
s.block(-48, -192, 448, 16, "Floor1")
climb_right(s, 0)
s.block(-48, -272, 120, 16, "RepeaterRoom")
s.repeater("repeater_stack", 20, -192)
s.enemy("Needle", 250, -194)
s.enemy("ScoutDrone", 300, -290)
# Floor 2 (-384), hole left, Anchor.
s.block(224, -384, 400, 16, "Floor2")
climb_left(s, -192)
s.anchor("stack_mid", 560, -384, -1)
s.enemy("Hopper", 380, -386)
s.enemy("Watcher", 612, -500)
# Floor 3 (-576), hole right, fragment closet.
s.block(-48, -576, 448, 16, "Floor3")
climb_right(s, -384)
s.block(-48, -652, 104, 16, "ClosetCeiling")
s.wall("stack_closet_wall", 40, -636, 16, 60, 25, scrap=40)
s.collectible(0, "sb_stack_closet", 12, -576, scrap=40)
s.collectible(1, "mf_lowlight_02", -10, -576, fragment="mf_lowlight_02")
s.enemy("Needle", 250, -578)
s.enemy("ScoutDrone", 220, -700)
# Floor 4 (-768), hole left, exit to the roofs on the right.
s.block(224, -768, 400, 16, "Floor4")
climb_left(s, -576)
s.enemy("Needle", 420, -770)
s.flow(-48, -382, 672, 372)
s.flow(-48, -960, 672, 536)
for y, c in [(-110, CYAN), (-300, AMBER), (-490, RED), (-680, GREEN), (-860, AMBER)]:
    s.neon(300, y, 26, 8, c)
for y in [0, -384, -768]:
    s.decor("pipes", 300, y - 140, 560, 12, "0.22, 0.22, 0.28, 1")
s.decor("crates", 100, 0, 28, 24, "0.22, 0.2, 0.25, 1")
s.decor("planter", 330, -576, 30, 16, "0.24, 0.2, 0.22, 1", "0.49, 0.8, 0.5, 1")
s.decor("lamp", 520, -768, 6, 60, "0.2, 0.2, 0.26, 1", "1, 0.72, 0.4, 1")
s.write(OUT + "ApartmentStack.tscn")

# ---------------------------------------------------------------- Neon Roofs
n = RoomGen("NeonRoofs", (-64, -500, 2500, 596), "lowlight", "Lowlight", "Neon Roofs")
n.block(-64, -500, 16, 304, "WallLeftUpper")
n.block(2420, -500, 16, 304, "WallRightUpper")
# The 112 px gap after roof 2 is the slide-jump gate: an early run-jump falls short.
roofs = [(-48, 448, -100), (480, 280, -100), (872, 308, -100), (1250, 250, -80), (1530, 470, -90), (2080, 356, -90)]
for i, (x, w, top) in enumerate(roofs):
    n.block(x, top, w, 96 - top, "Roof%d" % (i + 1))
# A missed slide-jump drops into a service well, not a pit: failing the
# teaching gap costs a few seconds of climbing, never a pip. The steps hug
# roof 2 so they can't be used to cross the gap.
n.block(760, 40, 112, 56, "GapWellFloor")
n.oneway(806, -8, 40)
n.oneway(764, -56, 34)
n.spawn("from_stack", 20, -100, 1, default=True)
n.spawn("from_power", 2380, -90, -1)
n.exit(-64, -196, 16, 96, "ApartmentStack", "from_roofs")
n.exit(2420, -186, 16, 96, "PowerBlock", "from_roofs")
n.hint("roofs_slidejump", 640, -196, 80, 96, "Wide gap: slide, then jump out of the slide", "")
n.flow(380, -480, 2040, 480)
# Optional high route to a Core Shard across a dodge-jump gap.
n.oneway(1400, -128, 60)
n.oneway(1480, -176, 120)  # scaffold deck: jump up through it, never bonk
n.block(1744, -176, 60, 30, "ShardLedge")
n.collectible(2, "cs_roofs", 1774, -176)
n.collectible(0, "sb_roofs_ledge", 1792, -176, scrap=50)
n.hint("roofs_dodgejump", 1500, -276, 90, 100, "Dodge, then jump mid-dodge to carry its speed", "")
# Watchers perch on short sign brackets hanging from the cables. Keep the
# bracket bottoms above head height (jump over, never a wall on the roof).
for x, y in [(700, -200), (1350, -230), (2150, -220)]:
    n.block(x - 2, y, 4, 60)
    n.enemy("Watcher", x, y - 2)
n.enemy("Needle", 600, -102)
n.enemy("Needle", 1000, -102)
n.enemy("Hopper", 1100, -102)
n.enemy("Hopper", 1650, -92)
n.enemy("Shield", 1850, -92)
n.enemy("ScoutDrone", 2250, -200)
n.hint("roofs_shield", 1760, -196, 60, 100, "Shields block from the front. Go behind, above, or [{action}] heavy.", "attack_heavy")
for x, top in [(100, -100), (620, -100), (1020, -100), (1400, -80), (1700, -90), (2300, -90)]:
    n.decor("ac", x, top, 22, 14, "0.24, 0.24, 0.3, 1")
n.decor("planter", 300, -100, 34, 16, "0.24, 0.2, 0.22, 1", "0.49, 0.8, 0.5, 1")
n.decor("cables", 900, -260, 700, 50, "0.18, 0.18, 0.24, 1")
for x, y, c in [(200, -140, RED), (560, -150, CYAN), (980, -170, AMBER), (1320, -120, GREEN), (1900, -150, RED), (2250, -130, VIOLET)]:
    n.neon(x, y, 36, 12, c, 5)
# Once the Power Block grid is rerouted, the Rainline's signal lamp past the
# east door comes back on (bible §13: the world answers progress).
live = n.switch("RainlineLive", "flag:lowlight_power_rerouted")
n.neon(2300, -260, 30, 10, CYAN, 5, parent=live)
n.write(OUT + "NeonRoofs.tscn")

# ---------------------------------------------------------------- Bell Tower (vertical)
# Floors every 240 px; four 48 px steps per climb.
b = RoomGen("BellTower", (-64, -1250, 704, 1346), "lowlight", "Lowlight", "Bell Tower")
b.block(-64, -1250, 16, 194, "WallLeftTop")
b.block(-64, -960, 16, 864, "WallLeftBottom")
b.block(624, -1250, 16, 98, "WallRightTop")
b.block(624, -1056, 16, 1056, "WallRight")
b.block(-48, 0, 672, BIG, "Floor0")
b.block(-48, -1250, 672, 40, "Ceiling")
b.spawn("from_rainline", 20, 0, 1, default=True)
b.spawn("from_lift", 20, -960, 1)
b.spawn("from_warden", 575, -1056, -1)
b.exit(-64, -96, 16, 96, "RainlineChase", "from_bell")
b.exit(624, -1152, 16, 96, "WardenTower", "from_bell")
b.exit(-64, -1056, 16, 96, "Relay", "from_lift", flag="shortcut_bell_lift")
b.gate(-48, -1056, 16, 96, closed=True, open_flag="shortcut_bell_lift", name="LiftGate")
def bell_climb_left(room, y0):
    for x, dy in [(100, 48), (170, 96), (100, 144), (150, 192)]:
        room.oneway(x, y0 - dy, 60)
def bell_climb_right(room, y0):
    for x, dy in [(500, 48), (430, 96), (500, 144), (420, 192)]:
        room.oneway(x, y0 - dy, 60)
# Floor 1 (-240), hole left.
b.block(200, -240, 424, 16, "Floor1")
bell_climb_left(b, 0)
b.enemy("Shield", 460, -242)
b.enemy("Needle", 320, -242)
# Floor 2 (-480), hole right, repeater + Enforcer.
b.block(-48, -480, 448, 16, "Floor2")
bell_climb_right(b, -240)
b.repeater("repeater_bell", 30, -480)
b.enemy("Enforcer", 220, -482)
b.enemy("ScoutDrone", 300, -590)
# Floor 3 (-720), hole left.
b.block(200, -720, 424, 16, "Floor3")
bell_climb_left(b, -480)
b.enemy("Shield", 380, -722)
b.enemy("Hopper", 480, -722)
b.enemy("Watcher", -38, -800, 1)
# Warden's office: tucked at the right end of floor 3, off the main path.
b.block(564, -796, 60, 16, "OfficeCeiling")
b.wall("bell_office_wall", 564, -780, 16, 60, 40, heavy=True, scrap=60)
b.collectible(0, "sb_bell_office", 590, -720, scrap=50)
b.collectible(1, "mf_lowlight_03", 602, -720, fragment="mf_lowlight_03")
# Floor 4 (-960): Anchor, lever, Warden's office, route to the arena.
b.block(-48, -960, 448, 16, "Floor4")
bell_climb_right(b, -720)
b.anchor("bell_top", 110, -960)
b.lever("shortcut_bell_lift", 40, -960, "Lift to the Relay is running")
b.oneway(460, -1008, 60)
b.oneway(540, -1056, 84)
b.flow(-48, -920, 672, 910)
for y, c in [(-120, RED), (-360, AMBER), (-600, CYAN), (-840, RED), (-1110, AMBER)]:
    b.neon(320, y, 28, 8, c)
b.decor("banner", 200, -1060, 24, 50, "0.3, 0.08, 0.12, 1", "1, 0.8, 0.7, 1")
b.decor("lamp", 250, -960, 6, 50, "0.2, 0.2, 0.26, 1", "1, 0.72, 0.4, 1")
for y in [-240, -480, -720]:
    b.decor("pipes", 300, y - 120, 560, 12, "0.22, 0.22, 0.28, 1")
b.write(OUT + "BellTower.tscn")

# ---------------------------------------------------------------- Warden Tower (boss)
# The arena is exactly one screen wide: the camera frames the whole fight, so
# nothing ever hits you from off-screen (bible §17).
w = RoomGen("WardenTower", (-64, -300, 544, 364), "lowlight", "Lowlight", "Warden Tower")
w.block(-64, -300, 16, 204, "WallLeftUpper")
w.block(464, -300, 16, 204, "WallRightUpper")
w.block(-48, -300, 512, 30, "Ceiling")
w.block(-48, 0, 512, BIG, "Floor")
w.spawn("from_bell", 16, 0, 1, default=True)
w.exit(-64, -96, 16, 96, "BellTower", "from_warden")
w.exit(464, -96, 16, 96, "Relay", "from_lift", flag="warden_krail_defeated")
w.gate(-32, -96, 16, 96, name="ArenaGateLeft")
w.gate(448, -96, 16, 96, closed=True, open_flag="warden_krail_defeated", name="ExitGate")
# Krail's boss test (D-071): the tower's own grid. Two high breakers (box
# tops -96, reached by jump + air light or any gun straight up) drop a clamp
# over the arena's centre. The west box (36..52, hurtbox 32..56) is clear of
# ArenaGateLeft (-32..-16). The arena one-ways sit next to the clamp column
# (120..172 and 244..296), so no grounded swing from standing on one (light
# chain, heavy or launcher, from its nearest end) reaches either box: from
# the old 60..124 / 300..364 a light swing did.
w.oneway(120, -72, 52)
w.oneway(244, -72, 52)
w.breaker("wt_grid_w", "wt_clamp", 36, -96)
w.breaker("wt_grid_e", "wt_clamp", 396, -96)
# Each box hangs on a cable from the ceiling (-270); the sag ends on its top.
CABLE = "0.2, 0.18, 0.24, 1"
for x in [44, 404]:
    w.decor("cables", x, -22, 6, 248, CABLE)
w.clamp("wt_clamp", 176, -270, 64, -120, "clamp_krail", ["wt_clamp"], hint_id="wt_clamp",
        hint="Breakers live. Drop the clamp on him.")
w.decor("pipes", 208, -2, 64, 2, AMBER)  # floor stripe under the footprint
w.neon(208, -250, 60, 14, "0.91, 0.16, 0.24, 1", 6, False)
w.decor("banner", 90, -150, 28, 60, "0.3, 0.08, 0.12, 1", "1, 0.8, 0.7, 1")
w.decor("banner", 330, -150, 28, 60, "0.3, 0.08, 0.12, 1", "1, 0.8, 0.7, 1")
# No centre pillar: the clamp column (176..240) is there, and decor draws
# over geometry, so a pillar would hide the slab and its countdown lamps.
for x in [0, 416]:
    w.decor("pillar", x, 0, 12, 270, "0.16, 0.15, 0.2, 1")
boss = w.enemy("WardenKrail", 330, -2)
w.raw("Triggers", "BossArena", "Area2D", ['position = Vector2(40, -250)', 'script = %s' % w._script("arena"),
      'size = Vector2(400, 250)', 'reward_position = Vector2(208, 0)', 'boss_path = NodePath("../../Enemies/%s")' % boss,
      'gate_paths = [NodePath("../../Geometry/ArenaGateLeft")]',
      'reward_scene = %s' % w._res("scene_DashModule", "PackedScene", "res://interactables/DashModule.tscn")])
w.write(OUT + "WardenTower.tscn")

finish()
