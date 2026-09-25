"""00 UNDERCITY: Medical Ruin (M7), the second room of the game.

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_medical_ruin.py          # write world/rooms/undercity/MedicalRuin.tscn
    python3 -B tools/roomgen/uc_medical_ruin.py --check  # exit 1 if the scene drifted

Purpose (bible §42, 0-5 min): the simple attack, the first enemies and the
heal lesson, one concept at a time (§23).
- Entrance: a corridor with the Pulse Blade on its rack. The campaign starts
  unarmed; the rack's 16x72 trigger spans the whole corridor height Rook can
  reach (his feet never rise above -56), so nobody walks past unarmed.
- A dormant orderly Needle (ai off, back turned) is a free practice target:
  30 HP is exactly one 10/10/14 chain. needle_dormant.tres drops no Scrap, so
  it adds nothing to the re-clear economy (D-089).
- Thesis: the red wind-up read at three heights, one Needle at a time
  (max_attackers 1): alone in the extraction pit, on flat ground, then on the
  gurney deck. Live Needles stand >= 420 px apart.
- Breathing space: the recovery ward (x 1440..1640) after the second live
  Needle, where the heal hint fires (Rook is probably hurt by then).
- Curiosity: the intake terminal (lore, optional) and the high shelf (Scrap).
- Landmark: the extraction pit, three empty chairs under a big flickering sea
  surgical lamp and a PULSE EXTRACTION banner. Exit: a sodium lamp.
No secrets, Anchor, Flow or real pits: the extraction pit is a 48 px catch
floor (48 down, 48 back up), so failing costs nothing but a step.
Route test: tests/unit/test_undercity_routes.gd::test_medical_ruin_route.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import OUT, BIG, SEA, SODIUM, CONCRETE, RUST, STEEL

m = RoomGen("MedicalRuin", (-64, -360, 2064, 456), "undercity", "Undercity", "Medical Ruin", max_attackers=1)

# --- Geometry: a long low ward under a concrete ceiling ---
m.block(-64, -360, 16, 264, "WallLeftUpper")      # door gap y -96..0 below it
m.block(-48, -360, 2032, 40, "Ceiling")           # underside -320
m.block(-48, 0, 528, BIG, "FloorA")               # entrance corridor, x -48..480
m.block(480, 48, 400, 48, "PitFloor")             # extraction pit, top +48, x 480..880 (48 down, 48 up)
m.block(880, 0, 1104, BIG, "FloorB")              # x 880..1984
m.block(1984, -360, 16, 264, "WallRightUpper")    # door gap y -96..0 below it
# The high shelf: floor -> one-way (48 up) -> shelf (48 up), each a plain
# jump (peak 56). Curiosity only; the main path walks underneath.
m.oneway(1000, -48, 56)                           # x 1000..1056, top -48
m.block(1072, -96, 96, 16, "Shelf")               # x 1072..1168, top -96
m.block(1700, -48, 160, 48, "GurneyDeck")         # x 1700..1860, a 48 step

# --- The Pulse Blade rack (bottom-centre origin, trigger y -72..0) ---
m.weapon_pickup("PulseBladeRack", "pulse_blade", "got_pulse_blade", 140, 0)

# --- Enemies: one concept at a time ---
# Dormant orderly, back turned: the first swing lands on something that
# never swings back.
m.enemy("Needle", 270, -2, 1, ai=False, data="needle_dormant")
m.enemy("Needle", 700, 46)                        # first live enemy, alone in the pit
m.enemy("Needle", 1360, -2)                       # reinforce on flat ground
m.enemy("Needle", 1780, -50)                      # reinforce on the deck: the same read at a new height

# --- Curiosity ---
m.npc("uc_terminal_intake", 420, 0, 1)            # figure=false, verb "Read"; sets read_uc_intake_log
m.collectible(0, "sb_uc_med_shelf", 1140, -96, scrap=20)

# --- Doors ---
m.spawn("from_wake", -20, 0, 1, default=True)
m.spawn("from_shaft", 1956, 0, -1)
m.exit(-64, -96, 16, 96, "undercity/Wake", "from_medical")
m.exit(1984, -96, 16, 96, "undercity/MaintenanceShaft", "from_medical")

# --- Hints (reused ids: a player who saw them in the slice is not re-told) ---
m.hint("alley_attack", 190, -96, 60, 96, "[{action}] attack", "attack_light")
m.hint("stack_heal", 1480, -96, 80, 96, "Hurt? Stand still and hold on: [{action}] uses an injector", "heal")

# --- Dressing (placeholder art, D-026; sea tubes = ambience, sodium = route) ---
m.decor("pipes", 216, -300, 520, 12, STEEL)                  # corridor service run
m.neon(60, -300, 28, 6, SEA, 2)                               # corridor tubes
m.neon(300, -300, 28, 6, SEA, 3, True)                        # ambience (a broken tube would be a secret cue)
m.decor("radio", 420, 0, 18, 14, STEEL, SEA)                  # the intake terminal's body
m.decor("crates", 30, 0, 26, 22, RUST)                        # dumped supply cases by the door
# The extraction pit (landmark): three chairs with chest clamps under the lamp.
for x in (560, 660, 760):
    m.decor("bench", x, 48, 30, 24, STEEL, SEA)
m.decor("cables", 680, -250, 240, 40, CONCRETE)               # lamp feeds
m.neon(680, -260, 60, 10, SEA, 5, True)                       # big surgical lamp
m.decor("banner", 680, -200, 72, 24, RUST, SEA)               # PULSE EXTRACTION
# Beyond the pit: storage shelving and the gurney deck.
m.decor("workbench", 1260, 0, 40, 20, STEEL, SEA)
m.decor("bench", 1740, -48, 34, 20, STEEL, SEA)               # gurneys on the deck
m.decor("bench", 1820, -48, 34, 20, STEEL, SEA)
# The recovery ward (breathing space): sea tubes, a row of cots.
m.neon(1500, -240, 30, 6, SEA, 2)
m.neon(1600, -240, 30, 6, SEA, 2)
m.decor("bench", 1480, 0, 34, 16, STEEL, SEA)
m.decor("bench", 1580, 0, 34, 16, STEEL, SEA)
m.decor("pillar", 1440, 0, 14, 320, CONCRETE)
m.decor("pillar", 1650, 0, 14, 320, CONCRETE)
# Exit: the first steady sodium lamp, marking the way on.
m.neon(1950, -120, 20, 8, SODIUM, 3, False)
m.decor("lamp", 1930, 0, 10, 80, STEEL, SODIUM)

m.write(OUT + "MedicalRuin.tscn")

finish()
