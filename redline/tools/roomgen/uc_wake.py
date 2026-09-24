"""00 UNDERCITY: Wake, the game's first room (M7, bible §23 / §42 0-5 min).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_wake.py          # write world/rooms/undercity/Wake.tscn
    python3 -B tools/roomgen/uc_wake.py --check  # exit 1 if the scene drifted

Thesis: movement is the toy. Rook wakes on slab 14 of 14 in a Civic
Recovery disposal ward ("HOLD FOR COLLECTION") with nothing in his hands and
learns, one verb at a time: move, a tap-jump over a cabinet, a held jump up
the 48 px ward step, interact (the shutter lever), one-way grating up to a
walkway and a harmless drop to the exit. No enemies, no hazards, no pits:
the whole room is breathing space. The first red is the Collector's eye
flickering behind an unreachable grate: danger shown at a safe distance.

Metrics (data/level/traversal_default.tres): every main-path rise is
<= 48 px; the optional sill sits 52 px above the ward floor, so only a
full held jump (56 px peak) lands it (the variable-jump reward). The
walkway drop is 144 px onto flat floor: no damage.
Doors must match the M7 door contracts (tests/unit/test_door_contracts.gd).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import SEA, SODIUM, RED, STEEL, CONCRETE, BIG, OUT

w = RoomGen("Wake", (-64, -300, 1344, 396), "undercity", "Undercity", "Wake", max_attackers=1)

# --- Shell ---
w.block(-64, -300, 16, 396, "WallLeft")           # the only way is right
w.block(-48, -300, 1312, 40, "Ceiling")           # underside -260
w.block(-48, 0, 1312, BIG, "Floor")
w.block(1264, -300, 16, 204, "WallRightUpper")    # door y -96..0

# --- Movement lessons, left to right ---
w.block(236, -24, 40, 24, "Cabinet")              # 24 px hop: a tap is enough
w.block(400, -48, 224, 48, "WardFloor")           # 48 px step, x 400..624: needs a held jump
w.oneway(540, -100, 60)                           # optional sill, 52 above WardFloor: a full 56 px jump only
w.collectible(0, "sb_uc_wake_sill", 570, -100, scrap=10)
# The shutter closes the ward until Rook uses a lever (the interact lesson).
w.gate(760, -260, 16, 260, closed=True, open_flag="uc_ward_shutter", name="WardShutter")
w.oneway(856, -48, 64)                            # grating steps (one-way: jump up through them)
w.oneway(936, -96, 64)
w.block(1016, -144, 128, 16, "Walkway")           # x 1016..1144; walk off its end: 144 px drop, no damage
w.lever("uc_ward_shutter", 720, 0, "The ward shutter grinds open")
# East-side lever (Lever2): a player walking in from MedicalRuin (backtrack,
# legacy saves routed from the Relay) can open the shutter from that side too.
w.lever("uc_ward_shutter", 800, 0, "The ward shutter grinds open")
w.collectible(0, "sb_uc_wake_walkway", 1120, -144, scrap=15)

# --- Entries and the door ---
w.spawn("start", 40, 0, 1, default=True, label="new game")   # slab 14 of 14; the campaign start
w.spawn("from_medical", 1236, 0, -1)
w.exit(1264, -96, 16, 96, "undercity/MedicalRuin", "from_wake")

# --- One-shot hints, one verb each ---
w.hint("uc_wake", -48, -140, 150, 140, "Alive. Something in your chest made sure of it.  Move  [{action}]", "move_right")
w.hint("uc_jump", 160, -96, 60, 96, "[{action}] jump - hold it to go higher", "jump")
w.hint("uc_interact", 660, -96, 80, 96, "[{action}] use", "interact")

# --- Landmark and dressing ---
for x, y in [(40, 0), (120, 0), (480, -48), (560, -48)]:
    w.decor("bench", x, y, 60, 14, CONCRETE)      # the empty slabs (13 empty; Rook's is at 40)
w.decor("banner", 300, -140, 30, 50, "0.3, 0.08, 0.12, 1", "0.8, 0.8, 0.75, 1")   # "HOLD FOR COLLECTION"
# The grate: decor only, above the walkway's jump headroom, so it is unreachable.
w.decor("pipes", 1080, -230, 120, 10, STEEL)
# The Collector's eye flickering behind the grate: the first red; it never attacks.
w.neon(1080, -236, 36, 8, RED, 2)
w.neon(120, -200, 30, 6, SEA, 3, True)            # flickering service tubes (ambience)
w.neon(480, -200, 30, 6, SEA, 3, True)
w.neon(1220, -120, 14, 6, SODIUM, 2, False)       # steady sodium lamp over the exit (route only)

w.write(OUT + "Wake.tscn")
finish()
