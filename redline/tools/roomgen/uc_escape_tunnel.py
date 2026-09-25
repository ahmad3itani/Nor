"""00 UNDERCITY: Escape Tunnel, the Undercity epilogue (M7).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_escape_tunnel.py          # write world/rooms/undercity/EscapeTunnel.tscn
    python3 -B tools/roomgen/uc_escape_tunnel.py --check  # exit 1 if the scene drifted

Thesis: the new Service Pistol at range (a Watcher perched out of blade
reach, shot diagonally from the tunnel floor), then the Core reinforced on
a short full-drain Flow Zone up four 48 px steps (FZ3: keep moving, keep
hitting), then breathing space with Orr's second radio call on the top
floor and the climb out into the Relay's warm light.
Curiosity: a panel over a ceiling recess that only the pistol reaches
(secret 3, 30 Scrap) and a Core Shard ledge 230 px past the top step: too
wide for everything but a Dash-jump (secret 4, a revisit after Krail).
Metrics: data/level/traversal_default.tres (48 px steps, dodge-jump 149,
dodge-jump + air dodge est. 210-225, dash-jump 237). No pits anywhere.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG, OUT, SEA, SODIUM, CYAN, CONCRETE, RUST, STEEL

t = RoomGen("EscapeTunnel", (-64, -560, 2064, 656), "undercity", "Undercity", "Escape Tunnel", max_attackers=1)

# ---------------------------------------------------------------- shell
t.block(-64, -560, 16, 464, "WallLeftUpper")      # the bay door below it: y -96..0
t.block(-48, -560, 608, 340, "CeilingLowA")       # x -48..560, underside -220: the low tunnel mouth
t.block(560, -560, 48, 300, "RecessTop")          # x 560..608, underside -260: the recess over the panel
t.block(608, -560, 44, 340, "CeilingLowB")        # x 608..652, underside -220
t.block(652, -560, 1332, 40, "CeilingHigh")       # x 652..1984, underside -520: the shaft opens up
t.block(-48, 0, 748, BIG, "FloorA")               # x -48..700, the tunnel floor
t.block(1984, -560, 16, 224, "WallRightTop")      # the Relay door below it: y -336..-240
t.block(1984, -240, 16, 336, "WallRightLow")

# ---------------------------------------------------------------- the pistol lesson
# The Watcher perches on a bracket hung from the low ceiling at x 420, out of
# blade reach (its body is 12 px, 20 px of headroom under -220). Its bracket
# blocks a straight-up shot from below, so the answer is the new pistol aimed
# diagonally from the tunnel floor (x ~220): 3 shots (18 HP, 6 per shot). Its
# bolt telegraphs 0.9 s and is visible from the bay door.
t.block(418, -200, 4, 40, "WatcherBracket")       # hangs -200..-160; the Watcher stands on top
t.enemy("Watcher", 420, -202)
t.hint("market_shoot", 120, -96, 60, 96, "[{action}] shoot - aim with the move keys", "ranged")   # reused id: one lesson, one hint

# Secret 3: a panel sealing the recess, 204 px over the floor: far out of
# blade reach (jump peak 56), two pistol shots aimed straight up.
t.wall("uc_tunnel_panel", 560, -236, 48, 16, 12, scrap=30)
t.neon(600, -250, 4, 20, SEA, 1, True, broken=True)            # a broken tube: the secret cue

# Landmark: the derailed tram the player squeezed past from the bay.
t.decor("train", 300, 0, 300, 60, RUST, STEEL)   # no sodium accent: sodium is the route
for x in [60, 250]:
    t.neon(x, -214, 36, 4, SEA, 3, True)          # dead service tubes in the tunnel mouth

# ---------------------------------------------------------------- FZ3: the climb
# Four 48 px steps up to the top floor, the steps only under full drain. The
# Needle and the Hopper refill the Core (+28 before the mode's multiplier),
# so a normal ~8 s pass never burns in any mode (D-085, K-50).
t.block(700, -48, 160, 144, "Step1")
t.block(860, -96, 160, 192, "Step2")
t.block(1020, -144, 160, 240, "Step3")
t.block(1180, -192, 160, 288, "Step4")
t.flow(690, -300, 650, 300)                       # x 690..1340, full drain
t.enemy("Needle", 940, -98)
t.enemy("Hopper", 1260, -194)
# Sodium marks only the way forward: one lamp per step, denser toward the Relay.
for x, y in [(730, -48), (890, -96), (1050, -144), (1210, -192), (1400, -240)]:
    t.decor("lamp", x, y, 6, 60, CONCRETE, SODIUM)

# ---------------------------------------------------------------- the top floor
# Breathing space (no Flow): Orr's second call, then the mouth to the Relay.
t.block(1340, -240, 644, 336, "TopFloor")         # x 1340..1984
t.npc("orr_radio", 1880, -240, -1)                # rule 0 after the boss: "Tell me that was you."
t.decor("radio", 1880, -280, 18, 14, STEEL, CYAN)
t.decor("pipes", 1660, -240, 120, 40, STEEL)
# The Relay's warm sodium glow at the right mouth (1950, -300).
t.neon(1936, -330, 40, 6, SODIUM, 3, False)
t.decor("lamp", 1950, -240, 6, 72, CONCRETE, SODIUM)

# Secret 4 (Dash revisit): two one-way gratings up to a -336 step, then the
# shard ledge 230 px away (x 1600 -> 1830). Dodge-jump (149) and dodge-jump
# + air dodge (est. 210-225) fall short; dash-jump reaches (237 incl. margin).
# The ledge underside (-320) clears Rook's head on the top floor (-274).
t.oneway(1440, -288, 60)                          # x 1440..1500
t.oneway(1500, -336, 100)                         # x 1500..1600
t.block(1830, -336, 60, 16, "ShardLedge")         # x 1830..1890
t.collectible(2, "cs_uc_tunnel_dash", 1860, -336)
t.mapmarker(1700, -360, "Too wide to jump", "ability:dash")
t.hint("alley_gap", 1500, -436, 100, 100, "Too far to jump. Maybe later.")   # reused id

# ---------------------------------------------------------------- doors
t.spawn("from_bay", -20, 0, 1, default=True)
t.spawn("from_relay", 1956, -240, -1)
t.exit(-64, -96, 16, 96, "undercity/CollectorBay", "from_tunnel")
t.exit(1984, -336, 16, 96, "lowlight/Relay", "from_undercity")
t.write(OUT + "EscapeTunnel.tscn")

finish()
