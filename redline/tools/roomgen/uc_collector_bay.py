"""00 UNDERCITY: Collector Bay, the first boss arena (bible §17, §23, §42).

Run from redline/ (-B: do not write __pycache__):
    python3 -B tools/roomgen/uc_collector_bay.py          # write world/rooms/undercity/CollectorBay.tscn
    python3 -B tools/roomgen/uc_collector_bay.py --check  # exit 1 if the scene drifted

Boss test "first boss builds confidence" (§23): one static screen, no
summons, no Flow Zone, no pits or spikes. The Collector Drone (M4) teaches
keep moving (the Press locks where Rook stands), dodge (Volley, Dive) and
sidestep (Sweep) over three low catwalks. The checkpoint is BrokenLift's
Anchor uc_lift, one room back (runback about 1.5 s); the intro is 2.6 s the
first time and 0.6 s on retries.

Layout (x 0 is the left edge, the floor is y 0):
- Vestibule x 16..40 outside the BossArena trigger (x 72..448): the crates
  and the banner read before ArenaGateLeft shuts behind Rook.
- Catwalks: left x 96..160 and right x 344..408 at 40 px, centre x 200..304
  at 80 px (every rise is at most 48 px, every gap 40 px: plain jumps).
- Secret: the vent-panel alcove over the vestibule, cued by a broken SEA
  tube inside it. Its floor (y -92) is 92 px above the vestibule floor, so it
  is reached only by a leftward jump from the left catwalk's edge (feet -40,
  a 52 px rise) onto the lip strip x 56..72 in front of the panel. The floor
  over the vestibule and ArenaGateLeft (x 16..56) is solid, so dropping out
  of the alcove lands in the arena, never outside the sealed gate. It is
  visible for the whole fight.
- Reward: the ServicePistolDrop lands at (252, 0) under the hatch spotlight.
  Its 24x150 trigger spans the centre catwalk and a jump from it, so every
  route from the left door to the right one takes it; BossArena respawns it
  on a revisit until it is picked up.
- ExitGate (right) opens with got_service_pistol, and the right exit also
  requires it: a Rook standing east of the drop when the Collector dies (the
  pistol lands 1.8 s after the defeat flag) has to walk back for it before
  the pistol lesson. After the win the BayLit sodium lamps come on.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG, OUT, SEA, SODIUM, CRATE, CRATE_ACCENT

c = RoomGen("CollectorBay", (0, -240, 480, 270), "undercity", "Undercity", "Collector Bay", max_attackers=1)

# --- Shell ---
c.block(0, -240, 480, 16, "Ceiling")               # underside -224
c.block(0, -224, 16, 128, "WallLeftUpper")         # left door below it (y -96..0)
c.block(16, -224, 48, 88, "VentRoof")              # x 16..64, y -224..-136: the alcove roof
c.block(448, -224, 32, 128, "WallRightUpper")
c.block(0, 0, 480, BIG, "Floor")

# --- Doors (door contracts: tests/unit/test_door_contracts.gd) ---
c.spawn("from_lift", 28, 0, 1, default=True)       # vestibule x 16..40, outside the trigger
# Inside the arena: an old save walking down from the Relay starts the fight from the right.
c.spawn("from_tunnel", 436, 0, -1)
c.exit(0, -96, 16, 96, "undercity/BrokenLift", "from_bay")
# The right door keys on the reward, not the win: the pistol spawns 1.8 s
# after the defeat flag (death_time + 0.2), and a Rook standing east of the
# drop would otherwise leave for the pistol lesson without the pistol.
c.exit(464, -96, 16, 96, "undercity/EscapeTunnel", "from_bay", flag="got_service_pistol")
c.gate(40, -92, 16, 92, name="ArenaGateLeft")      # open until the BossArena closes it
c.gate(448, -96, 16, 96, closed=True, open_flag="got_service_pistol", name="ExitGate")

# --- Fight space: three low catwalks over a flat floor ---
c.oneway(96, -40, 64)                              # left catwalk x 96..160 (40 rise, 40 gap)
c.oneway(200, -80, 104)                            # centre catwalk x 200..304
c.oneway(344, -40, 64)                             # right catwalk x 344..408

# --- Secret: the vent alcove (hook visible during the fight) ---
# The alcove floor is solid over the vestibule and ArenaGateLeft (x 16..56):
# only the lip in front of the panel (x 56..72) drops through, into the
# arena, so the secret never lets Rook out of a sealed fight.
c.block(16, -92, 40, 8, "VentFloor")               # alcove floor x 16..56
c.oneway(56, -92, 16)                              # vent lip x 56..72
c.neon(30, -120, 4, 20, SEA, 1, True, broken=True) # the secret cue, inside the alcove
c.wall("uc_collector_vent", 56, -136, 8, 44, 30)   # vent panel (any attack, not heavy-only)
c.collectible(0, "sb_uc_bay_vent", 32, -92, scrap=40)

# --- Landmark: the hatch spotlight and the Bell Tower lift cargo ---
c.decor("lamp", 252, -224, 6, 40, "0.2, 0.2, 0.26, 1", "1, 0.62, 0.2, 1")   # hatch spotlight
c.decor("cables", 120, -224, 8, 90, "0.16, 0.15, 0.2, 1")
c.decor("cables", 376, -224, 8, 90, "0.16, 0.15, 0.2, 1")
c.decor("pipes", 64, -200, 384, 10, "0.22, 0.22, 0.28, 1")
# The same crates as the Relay / Bell Tower lift: the story payoff (Civic
# Recovery has been hauling the lift's cargo down here).
c.decor("crates", 180, 0, 30, 26, CRATE, CRATE_ACCENT)
c.decor("crates", 290, 0, 30, 26, CRATE, CRATE_ACCENT)
# Placeholder for the "CIVIC RECOVERY -> BELL TOWER LIFT" banner (D-026).
c.decor("banner", 252, -170, 60, 20, "0.3, 0.08, 0.12, 1", "1, 0.8, 0.7, 1")

# --- The boss and its arena (M4 behaviour) ---
boss = c.enemy("CollectorDrone", 252, -144, -1)
c.raw("Triggers", "BossArena", "Area2D", ['position = Vector2(72, -224)', 'script = %s' % c._script("arena"),
      'size = Vector2(376, 224)', 'boss_id = "collector_drone"', 'boss_title = "COLLECTOR DRONE"',
      'boss_subtitle = "Civic Recovery Unit C-00"', 'intro_time = 2.6', 'reward_position = Vector2(252, 0)',
      'boss_path = NodePath("../../Enemies/%s")' % boss,
      'gate_paths = [NodePath("../../Geometry/ArenaGateLeft"), NodePath("../../Geometry/ExitGate")]',
      'reward_scene = %s' % c._res("scene_ServicePistolDrop", "PackedScene", "res://interactables/ServicePistolDrop.tscn")])

# --- Breathing space after the win: the sodium lamps come on ---
lit = c.switch("BayLit", "flag:collector_drone_defeated")
c.neon(120, -210, 20, 6, SODIUM, 3, False, parent=lit)
c.neon(376, -210, 20, 6, SODIUM, 3, False, parent=lit)

c.write(OUT + "CollectorBay.tscn")
finish()
