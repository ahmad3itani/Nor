"""00 UNDERCITY: First Pursuit (M7 room task FirstPursuit).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_first_pursuit.py          # write world/rooms/undercity/FirstPursuit.tscn
    python3 -B tools/roomgen/uc_first_pursuit.py --check  # exit 1 if the scene drifted

A long horizontal service tunnel in three sections (bible §23 "one concept at
a time", §42 minutes 5-15):
  A  quiet slide (x -48..700): pipe bundle 1 is sealed to the ceiling with a
     24 px slot; the slide is taught with nothing hunting Rook.
  B  chase (x 700..1760): the Collector eye (CeilingTracker, D-069) drops out
     of the red-ringed hatch and follows Rook along its rail (720..1620). The
     district thesis, "keep moving": it only locks after 1.0 s standing in its
     cone, so the cart-stack hop and the well run-jump are free stops. Sliding
     under sealed bundle 2 breaks its line; past lost_x it retracts for good.
  C  composition (x 1760..4144): the pursuit_mid respawn (pre-Anchor, D-088),
     a lone Hopper warm-up, pair 2 (Needle + Hopper), an optional high-ledge
     cache (secret 2, a taught run-jump) and Orr's radio, the first NPC, in
     the final breathing space.
Metrics: data/level/traversal_default.tres (run-jump reach 103 px; the well
and the cache gap are 80 and 96 px; main-path rises are 48 px at most).
No Anchor and no Flow Zone here (both come later in the district).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG, OUT, SEA, SODIUM, RED, CYAN, RUST, STEEL, CONCRETE

p = RoomGen("FirstPursuit", (-64, -420, 4224, 516), "undercity", "Undercity", "First Pursuit", max_attackers=2)

# --- Shell -----------------------------------------------------------------------
p.block(-64, -420, 16, 324, "WallLeftUpper")      # the door opening is y -96..0
p.block(4144, -420, 16, 324, "WallRightUpper")
p.block(-48, -420, 4192, 40, "Ceiling")           # underside -380
p.block(-48, 0, 1348, BIG, "FloorA")              # x -48..1300
p.block(1300, 64, 80, 32, "WellFloor")            # 80 px run-jump gap (reach 103) over a catch well
p.oneway(1320, 16, 40)                            # a fall costs no pip: 48 up to the step, 16 to either lip
p.block(1380, 0, 2764, BIG, "FloorB")             # x 1380..4144

# --- Section A: the quiet slide lesson ----------------------------------------
# Sealed to the ceiling so the only way on is the 24 px slot (Rook low is 16).
# It is visible from the door; the hint's 120 px runway (180..300) is long
# enough to reach slide speed from a standing start.
p.block(300, -380, 120, 356, "PipeBundle1")
p.hint("alley_slide", 180, -96, 60, 96, "Run and hold [{action}] to slide", "move_down")  # reused Lowlight id: taught once
for x in (60, 560):
    p.neon(x, -300, 4, 30, SEA, 3, True)          # dead service tubes, ambience only
p.decor("pipes", 180, -330, 200, 12, STEEL)
p.decor("pipes", 560, -300, 240, 12, STEEL)

# --- Section B: the chase -------------------------------------------------------
# Landmark: the round ceiling hatch with its red ring (x 700..760), where the
# eye lives. The ring only shows while the Collector is alive; after the boss
# the hatch hangs open and dark (HatchDead) and the eye never loads.
p.decor("ac", 730, -356, 60, 24, RUST)            # hatch housing, flush with the ceiling
live = p.switch("HatchLive", "!flag:collector_drone_defeated")
p.neon(730, -354, 56, 4, RED, 1, False, parent=live)
hatch = p.switch("HatchDead", "flag:collector_drone_defeated")
p.decor("cables", 730, -290, 8, 90, STEEL, parent=hatch)
p.decor("cables", 742, -300, 14, 70, RUST, parent=hatch)
p.hint("uc_pursuit", 700, -200, 120, 200, "Something up there is scanning for you. Keep moving.")
p.tracker("CollectorEye", (720, 1620), -350, 740, 1780, "collector_eye", visible_when="!flag:collector_drone_defeated")
p.block(1000, -48, 160, 48, "CartStack")          # x 1000..1160: a 48 px hop, a free stop under the eye
p.decor("train", 1220, 0, 120, 40, RUST)          # the derailed cart (landmark), tipped at the well
p.decor("pipes", 1300, -340, 300, 12, STEEL)
# Sealed like bundle 1; sliding under it breaks the eye's line (the rail ends
# at 1620, 20 px short of it).
p.block(1640, -380, 120, 356, "PipeBundle2")

# --- Section C: the composition -------------------------------------------------
# Past lost_x: the eye loads GONE for anyone who spawns or respawns here.
p.spawn("pursuit_mid", 1820, 0, 1)
p.respawn_point("pursuit_mid", 1800, -200, 16, 200)   # a death in C never replays A and B
p.neon(1900, -260, 4, 30, SEA, 3, True)
p.enemy("Hopper", 2760, -2)                       # warm-up, alone: 440 px from pair 2
p.enemy("Needle", 3200, -2)                       # pair 2 (max_attackers 2: only these two together)
p.enemy("Hopper", 3320, -2)
p.decor("crates", 2500, 0, 30, 26, RUST)
p.decor("pillar", 3000, 0, 14, 380, CONCRETE)

# Optional cache (secret 2): two one-way steps, a 120 px runway on the high
# ledge and a 96 px run-jump (reach 103) to the far ledge. A miss lands on
# the floor at 3680..3776, with no enemy near (pair 2 is 360 px back).
p.oneway(3440, -48, 60)                           # x 3440..3500
p.oneway(3500, -96, 60)                           # x 3500..3560
p.block(3560, -144, 120, 16, "HighLedge")         # x 3560..3680
p.block(3776, -144, 120, 16, "FarLedge")          # x 3776..3896
p.block(3820, -200, 76, 16, "CacheRoof")
p.wall("uc_pursuit_cache", 3820, -184, 16, 40, 20, scrap=20)
p.block(3880, -184, 16, 40, "CacheBack")
p.collectible(0, "sb_uc_pursuit_cache", 3856, -144, scrap=30)
p.neon(3800, -230, 4, 26, SEA, 1, True, broken=True)           # the broken tube over the cache roof: the secret cue

# Final breathing space: Orr's radio, the first NPC (figure=false, verb Listen).
p.npc("orr_radio", 3990, 0, -1)
p.decor("radio", 3990, -40, 18, 14, STEEL, CYAN)
p.neon(3998, -48, 4, 4, CYAN, 1, False)           # radio LED
p.decor("workbench", 3990, 0, 40, 40, RUST, CYAN)
p.hint("uc_radio", 3930, -96, 160, 96, "A radio is crackling.  [{action}]", "interact")
# Exit: a steady sodium lamp over the right door (sodium marks the route).
p.decor("lamp", 4100, -120, 6, 60, STEEL, SODIUM)
p.neon(4100, -110, 20, 4, SODIUM, 1, False)

# --- Doors (door contracts: tests/unit/test_door_contracts.gd) -------------------
p.spawn("from_shaft", -20, 0, 1, default=True)
p.spawn("from_lift", 4116, 0, -1)
p.exit(-64, -96, 16, 96, "undercity/MaintenanceShaft", "from_pursuit")
p.exit(4144, -96, 16, 96, "undercity/BrokenLift", "from_pursuit")
p.write(OUT + "FirstPursuit.tscn")

finish()
