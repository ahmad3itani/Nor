"""M7/M6 ScannerBeam test fixture, written with roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_security.py           # write tests/fixtures/security_lane.tscn
    python3 -B tools/roomgen/fixtures_security.py --check   # exit 1 if the fixture drifted

One flat lane with every beam kind, far enough apart that each test drives
one beam at a time: calibration LOW/HIGH/FULL (as in Security Station's
calibration lane), a live LOW, a live pulsing FULL and a searchlight on
circuit t_s. No Breaker node: Breaker.gd belongs to M5, so the tests drive
the circuit with EventBus.breaker_hit, the beam's only circuit input.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from lowlight_style import BIG

OUT = "tests/fixtures/"


def write_fixtures():
    r = RoomGen("security_lane", (-64, -420, 1480, 516), "lowlight", "Test", "Security lane")
    r.block(-64, -420, 16, 420, "WallLeft")
    r.block(1400, -420, 16, 420, "WallRight")
    r.block(-48, 0, 1448, BIG, "Floor")                  # x -48..1400
    r.scanner("cal_low", 100, "cal_low", -96, 0)
    r.block(198, -136, 28, 16, "HighHousing")
    r.scanner("cal_high", 210, "cal_high", -120, 0)
    r.block(310, -216, 24, 16, "FullHousing")
    r.scanner("cal_full", 320, "cal_full", -200, 0)
    r.scanner("low", 520, "low", -96, 0)
    r.scanner("pulse", 760, "full_pulse_14", -200, 0)
    r.scanner("searchlight", 1000, "searchlight", -200, 0, circuit="t_s")
    r.spawn("start", 20, 0, 1, default=True)
    r.write(OUT + "security_lane.tscn")


if __name__ == "__main__":
    write_fixtures()
    finish()
