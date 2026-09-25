"""Undercity palette and constants for the 00 UNDERCITY room generators.

Visual thesis: dead sea-green service tubes for ambience (they flicker; a
broken tube, neon(..., SEA, 1, True, broken=True), is a secret
cue and nothing else), warm sodium lamps only along the
route, Collector red only on the Collector, radio cyan only on Orr's radio.
Each room has its own generator, tools/roomgen/uc_<snake_room>.py, which
imports RoomGen, finish and this module, writes one room and calls finish().
"""
BIG = 96  # floor thickness
OUT = "world/rooms/undercity/"
SEA = "0.62, 0.8, 0.72, 1"        # flickering service tubes (ambience)
SODIUM = "0.85, 0.58, 0.3, 1"     # steady, route only
RED = "0.91, 0.16, 0.24, 1"       # the Collector only
CYAN = "0.35, 0.88, 0.91, 1"      # the radio only
CONCRETE = "0.16, 0.2, 0.19, 1"
RUST = "0.3, 0.22, 0.17, 1"
STEEL = "0.2, 0.24, 0.24, 1"
# The Relay / Bell lift crates in lowlight.py, so the lift reads the same.
CRATE = "0.3, 0.22, 0.16, 1"
CRATE_ACCENT = "1, 0.81, 0.35, 1"
