"""M7/M3 CeilingTracker (Collector eye) test fixture, written with roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_tracker.py           # write tests/fixtures/tracker_rail.tscn
    python3 -B tools/roomgen/fixtures_tracker.py --check   # exit 1 if the fixture drifted

The numbers mirror First Pursuit's section B (rail 720..1620 at y -350,
wake 740, lost 1780, a sealed pipe bundle 1640..1760 that breaks the line),
so tests/unit/test_tracker.gd exercises the real room's timing.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG

OUT = "tests/fixtures/"


def write_fixtures():
    r = RoomGen("tracker_rail", (-64, -420, 2080, 516), "undercity", "Test", "Tracker rail")
    r.block(-64, -420, 16, 420, "WallLeft")
    r.block(2000, -420, 16, 420, "WallRight")
    r.block(-48, 0, 2048, BIG, "Floor")              # x -48..2000
    r.block(1640, -380, 120, 356, "PipeBundle")      # sealed; 24 px slot under it
    r.tracker("CollectorEye", (720, 1620), -350, 740, 1780, "collector_eye")
    r.spawn("start", 100, 0, 1, default=True)
    r.spawn("east", 1900, 0, -1)
    r.write(OUT + "tracker_rail.tscn")


if __name__ == "__main__":
    write_fixtures()
    finish()
