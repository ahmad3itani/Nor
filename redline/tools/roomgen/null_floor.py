"""M9 Deep Rig stratum N5 "The Floor" (D3 §3.2 N5; T10 cut the strata to
three, so it follows Breaker Run): Warden Krail at the rig's tier.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/null_floor.py          # write world/rooms/challenge/NullFloor.tscn
    python3 -B tools/roomgen/null_floor.py --check  # exit 1 if the scene drifted

Boss test "the same fight, answered faster": the WardenTower frame copied
from lowlight.py (bounds, one-ways at 120..172 / 244..296, breakers
wt_grid_w/e with box tops at -96, the clamp over the centre), so the clamp,
breaker and Krail spacing the M7 tests pin still hold. The variant
(bosses/variants/WardenKrailNull.tscn, data warden_krail_null.tres) goes to
phase 2 at 90% health, telegraphs at 0.72 (above the 0.6 floor), summons
Hoppers and rests 0.6 s between phases; the clamp (clamp_null.tres) warns
0.9 s and rearms in 6 s. No reward, no exit: the stage goal fires on the
kill (ChallengeGoal on_boss) and a descent ends there. The red floor strip
marks the depth; nothing on it is text.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from null_style import BIG, OUT, THEME, DISTRICT, WHITE, GREY, RED

w = RoomGen("NullFloor", (-64, -300, 544, 364), THEME, DISTRICT, "The Floor", folder="challenge")
# Sealed walls: the run ends at the goal, so there is no door on either side.
w.block(-64, -300, 16, 300, "WallLeft")
w.block(464, -300, 16, 300, "WallRight")
w.block(-48, -300, 512, 30, "Ceiling")
w.block(-48, 0, 512, BIG, "Floor")
w.spawn("from_breaker", 16, 0, 1, default=True)
# WardenTower's grid, copied: one-ways beside the clamp column (no grounded
# swing reaches a breaker from them) and two high breakers on one circuit.
w.oneway(120, -72, 52)
w.oneway(244, -72, 52)
w.breaker("wt_grid_w", "wt_clamp", 36, -96)
w.breaker("wt_grid_e", "wt_clamp", 396, -96)
for x in [44, 404]:
    w.decor("cables", x, -22, 6, 248, GREY)
w.clamp("wt_clamp", 176, -270, 64, -120, "clamp_null", ["wt_clamp"])
w.decor("pipes", 208, -2, 64, 2, WHITE)  # floor stripe under the footprint
# The depth mark: a red strip at the arena's centre (visual only).
w.neon(168, -8, 80, 6, RED, 3, False)
for x in [0, 416]:
    w.decor("pillar", x, 0, 12, 270, GREY)
boss = w.enemy("WardenKrailNull", 330, -2)
w.raw("Triggers", "BossArena", "Area2D", ['position = Vector2(40, -250)', 'script = %s' % w._script("arena"),
      'size = Vector2(400, 250)', 'boss_id = "null_krail"', 'boss_title = "WARDEN KRAIL"', 'boss_subtitle = "Echo"',
      'boss_path = NodePath("../../Enemies/%s")' % boss])
w.goal(192, -96, 32, 96, "floor", on_boss="null_krail")
w.write(OUT + "NullFloor.tscn")

finish()
