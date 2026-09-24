"""M7/M5 Grid test fixtures (Breaker, PowerShutter, GridClamp), written with
roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_grid.py           # write tests/fixtures/grid_*.tscn
    python3 -B tools/roomgen/fixtures_grid.py --check   # exit 1 if the fixtures drifted

grid_shutter: a flat floor (x -48..800) with a floor breaker, a high breaker,
one timed shutter and a Needle (tests/unit/test_power_shutter.gd).
grid_clamp: Warden Tower's arena with the D2b breaker/clamp placement and
the real Krail + BossArena (tests/unit/test_boss_grid_clamp.gd).
grid_validator: deliberate placement errors for the content-protocol test.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import BIG

OUT = "tests/fixtures/"


def grid_shutter():
    r = RoomGen("grid_shutter", (-64, -270, 880, 400), "lowlight", "Test", "Grid shutter")
    r.block(-64, -270, 16, 270, "WallLeft")
    r.block(800, -270, 16, 270, "WallRight")
    r.block(-48, 0, 848, BIG, "Floor")              # x -48..800
    r.breaker("t_fb", "t1", 60, -40)                # floor breaker: box -40..-16
    r.breaker("t_hb", "t2", 400, -96)               # high breaker: box -96..-72
    r.shutter("S", 176, -200, 16, 200, "t1", "shutter_run", "t_latched")
    r.wall("t_wall", 720, -48, 16, 48)              # a secret wall a launched body must not break
    r.enemy("Needle", 600, -2)
    r.spawn("start", 218, 0, -1, default=True)
    r.write(OUT + "grid_shutter.tscn")


def grid_clamp():
    # Warden Tower's arena (tools/roomgen/lowlight.py), exits walled off.
    r = RoomGen("grid_clamp", (-64, -300, 544, 364), "lowlight", "Test", "Grid clamp")
    r.block(-64, -300, 16, 300, "WallLeft")
    r.block(464, -300, 16, 300, "WallRight")
    r.block(-48, -300, 512, 30, "Ceiling")
    r.block(-48, 0, 512, BIG, "Floor")              # x -48..464
    r.spawn("from_bell", 16, 0, 1, default=True)
    r.gate(-32, -96, 16, 96, name="ArenaGateLeft")
    r.oneway(60, -72, 64)
    r.oneway(300, -72, 64)
    r.breaker("wt_grid_w", "wt_clamp", 36, -96)
    r.breaker("wt_grid_e", "wt_clamp", 396, -96)
    r.clamp("wt_clamp", 176, -270, 64, -120, "clamp_krail", ["wt_clamp"], hint_id="t_clamp",
            hint="Breakers live: drop the clamp on him")
    boss = r.enemy("WardenKrail", 330, -2)
    r.raw("Triggers", "BossArena", "Area2D", ['position = Vector2(40, -250)', 'script = %s' % r._script("arena"),
          'size = Vector2(400, 250)', 'boss_path = NodePath("../../Enemies/%s")' % boss,
          'gate_paths = [NodePath("../../Geometry/ArenaGateLeft")]'])
    r.write(OUT + "grid_clamp.tscn")


def grid_validator():
    # Everything here is wrong on purpose (test_validator_* in test_power_shutter).
    r = RoomGen("grid_validator", (-64, -270, 880, 400), "lowlight", "Test", "Grid validator")
    r.block(-48, 0, 848, BIG, "Floor")
    r.spawn("start", 40, 0, 1, default=True)
    r.breaker("v_high", "v1", 100, -130)            # box top at floor -130: above the -96 limit
    r.breaker("v_orphan", "v_nobody", 200, -40)     # nothing consumes circuit:v_nobody
    r.shutter("V", 400, -200, 16, 120, "v1", "shutter_run", "")   # no latch, ends 80 px above the floor
    r.write(OUT + "grid_validator.tscn")


if __name__ == "__main__":
    grid_shutter()
    grid_clamp()
    grid_validator()
    finish()
