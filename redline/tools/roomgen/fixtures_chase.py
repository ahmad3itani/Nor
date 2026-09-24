"""M7 chase test fixture (ChaseDirector + Pursuer), written with roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_chase.py           # write tests/fixtures/chase_flat.tscn
    python3 -B tools/roomgen/fixtures_chase.py --check   # exit 1 if the fixture drifted

chase_flat: a flat line with one 90 px pit (x 900..990). The path runs east
from 0 to 1700; start_area (360..440) holds the `start` spawn, so the chase
arms on the first frame; `east` (1680) is the far end for the arming rule and
the end-ignored-in-IDLE tests; `west` (100) is the respawn point west of
start_area (tests point the last Anchor at it). The exit loops to `east`, so
walking into it never leaves the fixture.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish, q
from lowlight_style import BIG

OUT = "tests/fixtures/"
FIXTURE = "res://tests/fixtures/chase_flat.tscn"


def write_fixtures():
    r = RoomGen("chase_flat", (-64, -270, 1800, 400), "lowlight", "Test", "Chase flat")
    r.block(-64, 0, 964, BIG, "FloorWest")
    r.block(990, 0, 746, BIG, "FloorEast")    # pit 900..990
    r.spawn("start", 400, 0, 1, default=True)
    r.spawn("east", 1680, 0, -1)
    r.spawn("west", 100, 0, 1)
    r.chase("test", "test_chase", [(0, 0), (1700, 0)], [], (360, -64, 80, 64), (1560, -64, 40, 64), [(380, 0), (1040, 0)])
    # Exit at the east edge, back into this fixture (roomgen's exit() only
    # targets world rooms).
    r.add("Triggers", "Exit", "Area2D", ['position = Vector2(1720, -96)', 'script = %s' % r._script("exit"), 'size = Vector2(16, 96)',
                                         'target_room = %s' % q(FIXTURE), 'target_entry = &"east"'])
    r.write(OUT + "chase_flat.tscn")


if __name__ == "__main__":
    write_fixtures()
    finish()
