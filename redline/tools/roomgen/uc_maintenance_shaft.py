"""00 UNDERCITY: Maintenance Shaft (M7, sequence 3 of 6; vertical).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_maintenance_shaft.py          # write world/rooms/undercity/MaintenanceShaft.tscn
    python3 -B tools/roomgen/uc_maintenance_shaft.py --check  # exit 1 if the scene drifted

Purpose (bible §42, 5-15 min): dodge, the air attack, the climbing rhythm,
the first enemy composition (Floor 2), the first secret (the closet) and
an optional side pocket (the Relay crew ledge).

Section 41 checklist:
  Entrance     the pump room (floor 0) under a giant rusted pump wheel
  Movement     three zig-zag climbs of 48 px steps, plus an optional 92 px
               run-jump to the crew ledge (reach 103, 11 spare)
  Thesis       dodge through the Scout's slow bolt, jump-attack it; then the
               first composition: Needle + Scout on Floor 2, both taught
               alone first (one concept at a time: the new thing is the pair)
  Curiosity    a cracked closet wall under a broken SEA tube, and the crew
               ledge seen from the exit ledge
  Landmark     the pump wheel, and a column of steady sodium lamps (one per
               climb plus the exit ledge) that marks the route
  Breathing    Floor 1 after its Needle; the crew pocket and the exit ledge
  Exit         a sodium-lit ledge at the top right

No Anchor and no Flow Zone here. Metrics: data/level/traversal_default.tres
(every main-path rise is 48 px, the widest step-to-ledge gap is 20 px, the
ceiling underside -940 leaves 82 px of headroom over a crew-ledge jump).
Missing the optional jump drops Rook onto Floor 2 or Floor 1: no damage,
about 6 s of re-climb.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG, OUT, SEA, SODIUM, CONCRETE, RUST, STEEL

# max_attackers 2: the Floor 2 pair is the first composition and both may
# threaten at once (the room's only place with two awake enemies in reach).
s = RoomGen("MaintenanceShaft", (-64, -980, 704, 1076), "undercity", "Undercity", "Maintenance Shaft", max_attackers=2)

# ---------------------------------------------------------------- shell
s.block(-64, -980, 16, 884, "WallLeftUpper")      # the MedicalRuin door is y -96..0
s.block(-48, -980, 672, 40, "Ceiling")            # underside -940
s.block(624, -980, 16, 164, "WallRightTop")       # the FirstPursuit door is y -816..-720
s.block(624, -720, 16, 720, "WallRight")
s.block(-48, 0, 672, BIG, "Floor0")               # the pump room

# ---------------------------------------------------------------- climb A (right hole) -> Floor 1
for x, y in [(500, -48), (420, -96), (500, -144), (420, -192)]:
    s.oneway(x, y, 60)
s.block(-48, -240, 448, 16, "Floor1")             # x -48..400; 20 px from the last step

# ---------------------------------------------------------------- climb B (left hole) -> Floor 2
for x, y in [(70, -288), (150, -336), (70, -384), (150, -432)]:
    s.oneway(x, y, 60)
s.block(224, -480, 400, 16, "Floor2")             # x 224..624; 14 px from the last step

# ---------------------------------------------------------------- secret 1: the closet (first secret)
# A 64 px nook at the right end of Floor 2, sealed by a cracked wall. The cue
# is a broken SEA tube hanging askew above it (never sodium: sodium is the
# route). Two light blade hits break it.
s.block(544, -556, 80, 16, "ClosetCeiling")
s.wall("uc_shaft_closet", 544, -540, 16, 60, 20)
s.neon(530, -600, 4, 30, SEA, 1, True)
s.collectible(0, "sb_uc_shaft_closet", 578, -480, scrap=30)
s.collectible(1, "mf_undercity_01", 604, -480, fragment="mf_undercity_01")

# ---------------------------------------------------------------- climb C -> exit ledge
for x, y in [(460, -528), (380, -576), (460, -624), (380, -672)]:
    s.oneway(x, y, 56)
s.oneway(440, -720, 184)                          # exit ledge x 440..624

# ---------------------------------------------------------------- optional side pocket: the Relay crew stash
# Seen from the exit ledge: one 48 px step up, then a 92 px run-jump from a
# 100 px runway (reach 103). The note foreshadows Orr's crew and the Anchor.
s.oneway(300, -768, 100)                          # x 300..400, 40 px from the exit ledge
s.block(-48, -768, 256, 16, "CrewLedge")          # x -48..208
s.collectible(0, "sb_uc_shaft_crew", 40, -768, scrap=20)
s.npc("uc_note_crew", 110, -768, 1)               # figure=false, verb "Read"

# ---------------------------------------------------------------- enemies (22 Scrap first clear)
# The Scout's single slow bolt (0.7 s wind-up) teaches dodge-through and the
# air attack in an open room; Floor 1's lone Needle is a melee refresher;
# Floor 2 pairs them (the Needle walks 224..544, stopped by the closet wall;
# the Scout hovers 110 px above Floor 2, left of climb C).
s.enemy("ScoutDrone", 320, -120)
s.enemy("Needle", 250, -242)
s.enemy("Needle", 420, -482)                      # 158 px from the -432 step landing at x 262
s.enemy("ScoutDrone", 330, -590)

# ---------------------------------------------------------------- doors (door contracts)
s.spawn("from_medical", -20, 0, 1, default=True)
s.spawn("from_pursuit", 596, -720, -1)
s.exit(-64, -96, 16, 96, "undercity/MedicalRuin", "from_shaft")
s.exit(624, -816, 16, 96, "undercity/FirstPursuit", "from_shaft")

# ---------------------------------------------------------------- hints (the pump room)
s.hint("alley_dodge", 20, -96, 80, 96, "[{action}] dodge - it passes through attacks", "dodge")   # reused id
s.hint("uc_air", 180, -96, 60, 96, "Jump, then [{action}] to reach things above you", "attack_light")

# ---------------------------------------------------------------- landmark and dressing
s.decor("ac", 200, 0, 60, 60, RUST, SODIUM)       # the giant rusted pump wheel
s.decor("pipes", 150, -140, 300, 12, STEEL)
s.decor("pipes", 450, -300, 300, 12, STEEL)
s.decor("cables", 300, -860, 560, 40, CONCRETE)
for x in [-30, 400]:
    s.decor("pillar", x, 0, 12, 96, CONCRETE)
# Steady sodium lamps: one per climb and one on the exit ledge (the route).
for x, y in [(560, -60), (110, -300), (420, -560), (560, -760)]:
    s.neon(x, y, 16, 6, SODIUM, 2, False)
# Dead service tubes for ambience (they flicker).
s.neon(20, -180, 24, 6, SEA, 3, True)
s.neon(300, -420, 24, 6, SEA, 3, True)
s.neon(60, -700, 24, 6, SEA, 3, True)

s.write(OUT + "MaintenanceShaft.tscn")
finish()
