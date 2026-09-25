"""01 LOWLIGHT: Smuggler Route, an optional loop (M7, D-075).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/ll_smuggler_route.py          # write world/rooms/lowlight/SmugglerRoute.tscn
    python3 -B tools/roomgen/ll_smuggler_route.py --check  # exit 1 if the scene drifted

A smugglers' canal under Neon Roofs, from the Power Block basement (east)
to the Apartment Stack ground floor (west). First run is east to west:

  Pump Room   a HIGH breaker (shoot up, or jump + air attack) runs the
              `shutter_run` countdown; the Hopper is fought before it.
  Floodway    W1 run-jump, the 24 px pipe slot, W2 slide-jump over the
              culvert catch (a miss costs nothing and climbs out to P2's
              east end), W3 run-jump (a miss is a pit: 1 pip, back on P3).
  Floodgate   the landmark; its 24 px slot is the way on. On its face, the
              Dash shrine 64 px below the DashLedge across 282 px: a
              dash-jump lands with ~13 px to spare; a dodge-jump plus an air
              dodge on any airborne frame falls ~13 px short (swept frame by
              frame; only a whole-coyote-window take-off can still make it).
  Den         candle-warm safe house: Anchor, Iko (first meeting, then she
              moves to the Relay), the heavy-wall cache on the loft, and
              the lever that unbolts the hatch to the Stack. The Flow Zone
              covers only the den raid (x >= 300).

Level metrics: data/level/traversal_default.tres (run-jump 103, slide-jump
118, dodge-jump 149, dash-jump 237, all on the flat; steps <= 48 px). Tests:
tests/unit/test_lowlight_m7_routes.gd (the test_smuggler_* functions).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import OUT, AMBER, VIOLET

s = RoomGen("SmugglerRoute", (-64, -540, 2500, 700), "lowlight", "Lowlight", "Smuggler Route")
s.block(-64, -540, 16, 444, "WallWestUpper")
s.block(2420, -540, 16, 444, "WallEastUpper")
s.block(-48, -540, 2468, 40, "Canopy")

# ---------------------------------------------------------------- Pump Room (safe, no Flow)
s.block(1820, 0, 600, 96, "PumpFloor")
# HIGH breaker (box -96..-72): shoot straight up, or jump + air light.
s.breaker("sr_pump", "sr_pump", 2192, -96)
# A conduit drops from the canopy to the box, so the eye follows it up.
# (Decor origin is bottom-centre; "cables" sag sideways, so a thin pillar.)
s.decor("pillar", 2200, -96, 2, 404, "0.2, 0.2, 0.26, 1")
# Latches for good once crossed, so the loop is free on every later visit.
s.shutter("SR", 1960, -200, 16, 200, "sr_pump", "shutter_run", "sr_shutter_latched")
s.enemy("Hopper", 2080, -2)  # fought before the breaker

# ---------------------------------------------------------------- Floodway (no Flow)
# W1 1724..1820 (96 px, run-jump; landing ~1717).
s.block(1464, 0, 260, 16, "P2")
# 24 px slot, 48 px long; 87 px of flat from the W1 landing to the pipe.
s.block(1582, -200, 48, 176, "Pipe")
# W2 1352..1464 (112 px, slide-jump). The culvert catches a miss (no pip);
# its only way out is the one-way under P2's east end (48 px, then 24 px).
s.block(1330, 72, 420, 16, "Culvert")
s.oneway(1728, 24, 40)
# W3 1104..1200 (96 px, run-jump; 146 px of P3 run-up). A miss is a pit
# (the floodwater kill plane) and respawns Rook on P3.
s.block(1200, 0, 152, 16, "P3")

# ---------------------------------------------------------------- Floodgate (landmark)
s.block(640, 0, 464, 96, "Sill")
s.block(692, -420, 48, 396, "Floodgate")  # 24 px slot under it, 48 px long
# Dash gate. Distance alone cannot separate Dash from dodge at one height: a
# dodge-jump plus an air dodge after the apex hang reaches ~229 px on the flat
# against the dash-jump's 242 (the old 234 px shrine at the ledge's height
# leaked). A drop widens the split, because the dash keeps its speed while
# falling and an air dodge only buys 13 flat frames: 64 px down, the
# dash-jump reaches ~289 px and the best dodge ~258. So the shrine sits 64 px
# below the ledge across 282 px (margins ~13 px each way, swept frame by
# frame in test_smuggler_dash_shard_negative_sweep, at the lip and 8 px
# past it). Taking off at the very end of the coyote window (16-20 px past
# the lip) plus a frame-exact air dodge can still land: a mastery trick the
# map marker owns up to ("(mostly)", K-48).
# Steps up to the DashLedge. The ledge and the top step are one-ways stacked
# over the -144 step (jumped up through), so every take-off at or above the
# shrine's height is at least 282 px from it; the -144 step is 32 px below
# the shrine and 270 px away, ~50 px out of a dodge's reach.
for x, y, w in [(1048, -48, 56), (1000, -96, 40), (1048, -144, 56), (1064, -192, 40)]:
    s.oneway(x, y, w)
s.oneway(1060, -240, 44)  # DashLedge
# Dash shrine on the floodgate's face, 740..778 at -176. A miss drops
# harmlessly onto the Sill.
s.block(740, -176, 38, 16, "Shrine")
s.collectible(2, "cs_smuggler_dash", 759, -176)
s.mapmarker(950, -280, "Too wide to jump (mostly)", "ability:dash")
s.enemy("ScoutDrone", 900, -150)

# ---------------------------------------------------------------- Den (safe house)
s.block(-48, 0, 688, 96, "DenFloor")
s.oneway(320, -48, 56)
s.oneway(264, -96, 48)
s.block(30, -144, 230, 16, "Loft")
# Loft cache: a pocket x 30..100 behind a heavy-only wall (heavy attacks).
s.block(14, -240, 16, 96, "CacheWallW")
s.block(30, -240, 86, 16, "CacheCeiling")
s.wall("sr_den_cache", 100, -224, 16, 80, 40, heavy=True, scrap=60)
s.collectible(0, "sb_sr_cache", 60, -144, scrap=60)
s.lever("shortcut_smuggler_route", 40, 0, "Hatch unbolted. The Stack is through here; the den Anchor gets you back to the Power Block.")
s.gate(-48, -96, 16, 96, closed=True, open_flag="shortcut_smuggler_route", name="Hatch")
s.anchor("smuggler_den", 230, 0)
# First meeting only: after iko_intro sets met_iko she moves to the Relay (D-076).
s.npc("iko", 150, 0, 1, present_when=["!flag:met_iko"])
s.enemy("Needle", 380, -2, 1)
s.enemy("Shield", 520, -2, 1)  # the den raid
# The raid only; the Anchor / Iko / lever side (x < 300) is safe.
s.flow(300, -300, 392, 300)

# ---------------------------------------------------------------- Dressing
# Violet chalk eyes mark both ends of the route (and the floodgate).
for x, y in [(2300, -150), (716, -460), (-20, -130)]:
    s.neon(x, y, 20, 10, VIOLET, 3)
# Candle-warm den: low amber lamps, crates of contraband, a bench.
WARM = "0.32, 0.24, 0.2, 1"
for x in [96, 196, 276]:
    s.decor("lamp", x, -2, 6, 40, WARM, "1, 0.72, 0.4, 1")
s.decor("crates", 470, 0, 30, 24, "0.3, 0.22, 0.16, 1")
s.decor("crates", 600, 0, 26, 26, "0.3, 0.22, 0.16, 1")
s.decor("bench", 180, -144, 30, 12, WARM)
s.neon(150, -80, 16, 8, AMBER, 2)
# The floodway: dead pumps and pipes.
s.decor("pipes", 1480, -300, 260, 12, "0.2, 0.22, 0.28, 1")
s.decor("pipes", 1880, -260, 300, 12, "0.2, 0.22, 0.28, 1")

# ---------------------------------------------------------------- Doors
s.spawn("from_power", 2380, 0, -1, default=True)
s.spawn("from_stack", 20, 0, 1)
s.exit(2420, -96, 16, 96, "PowerBlock", "from_smuggler")
s.exit(-64, -96, 16, 96, "ApartmentStack", "from_smuggler", flag="shortcut_smuggler_route")
s.hint("sr_eye", 2240, -96, 100, 96, "A chalk eye. Someone uses this route.")
s.hint("alley_gap", 1060, -340, 44, 100, "Too far to jump. Maybe later.")  # reused id (D-066): same lesson, same text
s.write(OUT + "SmugglerRoute.tscn")

finish()
