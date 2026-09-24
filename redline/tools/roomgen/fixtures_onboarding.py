"""M7 onboarding test fixtures (M1: unarmed start, weapon pickups,
pre-Anchor respawn, EntryCheckpoint), written with roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_onboarding.py           # write tests/fixtures/onboarding_*.tscn
    python3 -B tools/roomgen/fixtures_onboarding.py --check   # exit 1 if the fixtures drifted

Used by tests/unit/test_onboarding.gd:
- onboarding_a: start, a Pulse Blade rack at x 140, a dormant Needle at
  x 270, and an exit to onboarding_b (from_a).
- onboarding_b: entry from_a, a Flow Zone, the Anchor ob_anchor, a mid-room
  EntryCheckpoint for ob_mid (x 580) and a one-way platform (y -80, x
  700..800) with the Service Pistol drop under its middle (x 750, 0).
- onboarding_badcheckpoint: an EntryCheckpoint naming a spawn that does not
  exist (the validator must report it).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG

OUT = "tests/fixtures/"
BOUNDS = (-64, -270, 1100, 400)


def _exit_to_fixture(g, name, x, target, entry):
    # exit() maps targets into res://world/rooms/, so a fixture door is raw
    # (like the hand-written WorldA/WorldB fixtures).
    g.raw("Triggers", name, "Area2D", ['position = Vector2(%d, -96)' % x, 'script = %s' % g._script("exit"),
        'size = Vector2(16, 96)', 'target_room = "res://tests/fixtures/%s.tscn"' % target, 'target_entry = &"%s"' % entry])


def room_a():
    g = RoomGen("onboarding_a", BOUNDS, "undercity", "Test", "Onboarding A")
    g.block(-48, 0, 1084, BIG, "Floor")
    g.spawn("start", 40, 0, 1, default=True)
    g.weapon_pickup("PulseBladeRack", "pulse_blade", "got_pulse_blade", 140, 0)
    g.enemy("Needle", 270, 0, ai=False)
    _exit_to_fixture(g, "ExitB", 1020, "onboarding_b", "from_a")
    g.write(OUT + "onboarding_a.tscn")


def room_b():
    g = RoomGen("onboarding_b", BOUNDS, "undercity", "Test", "Onboarding B")
    g.block(-48, 0, 1084, BIG, "Floor")
    g.spawn("from_a", 40, 0, 1, default=True)
    g.flow(160, -200, 240, 200)
    g.spawn("ob_mid", 600, 0, 1)
    g.respawn_point("ob_mid", 580, -200, 16, 200)
    g.oneway(700, -80, 100)
    g.weapon_pickup("ServicePistolDrop", "service_pistol", "got_service_pistol", 750, 0)
    g.anchor("ob_anchor", 950, 0)
    g.write(OUT + "onboarding_b.tscn")


def room_bad_checkpoint():
    g = RoomGen("onboarding_badcheckpoint", BOUNDS, "undercity", "Test", "Onboarding bad checkpoint")
    g.block(-48, 0, 1084, BIG, "Floor")
    g.spawn("start", 40, 0, 1, default=True)
    g.respawn_point("nowhere", 300, -200, 16, 200)
    g.write(OUT + "onboarding_badcheckpoint.tscn")


if __name__ == "__main__":
    room_a()
    room_b()
    room_bad_checkpoint()
    finish()
