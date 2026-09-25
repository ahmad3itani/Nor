# REDLINE Districts

Bible §36 M7: "Every district requires a mechanic thesis, visual thesis, enemy ecosystem and boss test." This sheet gives those four lines for each built district, plus the bible §41 row: where the district's idea is **introduced**, **reinforced**, **combined** and **tested**. The district's palette values are in `ART_BIBLE.md` §3, the decisions behind each line in `DECISIONS.md` (D-061..D-104), and the rooms themselves in `world/rooms/<district>/` with one generator each in `tools/roomgen/`.

Built so far: Act I, batch 1 (M7). **00 Undercity** is the opening district and **01 Lowlight** is complete. The Relay is the hub between them. Ironworks and later districts are batch 2+ and not started.

| | 00 Undercity | 01 Lowlight |
|---|---|---|
| Rooms | Wake, Medical Ruin, Maintenance Shaft, First Pursuit, Broken Lift, Collector Bay (boss), Escape Tunnel | Flooded Alley, Market Run, Apartment Stack, Neon Roofs, Power Block, Security Station, Rainline Chase, Bell Tower, Warden Tower (boss), plus the optional Smuggler Route loop |
| Anchors | `uc_lift` (the first Anchor) | `stack_mid`, `power_block`, `smuggler_den`, `rainline_platform`, `bell_top` (plus `relay` in the hub) |
| Unlock | Pulse Blade (rack), Service Pistol (Collector reward) | Dash (dropped by Warden Krail) |
| Theme | `data/districts/undercity.tres` | `data/districts/lowlight.tres` |

---

## 00 UNDERCITY

**Mechanic thesis: *Keep moving.*** Standing still is what the Collector hunts. Its eye (`CeilingTracker`, `data/props/collector_eye.tres`) builds a lock only while Rook is nearly still in its ±32 px cone and fires after 1.0 s of lock. Flow Zones drain the Core while Rook lingers, and hits refill it. Every Undercity lesson is "move through it": there are no spikes or pits that ignore i-frames (D-067), only catch wells.

**Visual thesis: a flooded civic disposal complex.**
- Sea-green flickering service tubes are the ambience. A *broken* sea-green tube (hung askew, half lit, stuttering: `NeonSign.broken`, D-104) is a secret cue, and marks every Undercity secret wall.
- Steady sodium lamps mark the route, and only the route.
- Red belongs to the Collector alone: the eye, its hatch ring, the drone.
- Cyan belongs to Orr's radio alone.
- Geometry is concrete, rust and steel. Seepage drips as a thin vertical rain.
- Landmarks: the ward of slabs (Wake), the extraction pit (Medical Ruin), the pump wheel (Maintenance Shaft), the ceiling hatch (First Pursuit), the hanging lift car (Broken Lift), the hatch spotlight and the Bell Tower lift crates (Collector Bay), the derailed tram (Escape Tunnel).

**Enemy ecosystem: few bodies, one concept at a time (§23).**

| Enemy | Role here | Where |
|---|---|---|
| Needle | The first melee enemy. The dormant orderly (`needle_dormant.tres`, drops 0 Scrap) is a free practice target | Medical Ruin (1 dormant, 3 live), Maintenance Shaft (2), First Pursuit (1), Broken Lift (1 `needle_ledge`), Escape Tunnel (1) |
| Scout Drone | The dodge teacher: one slow bolt | Maintenance Shaft (2, Floor 2 is the first composition with a Needle) |
| Hopper | Vertical pressure inside compositions | First Pursuit (2), Escape Tunnel (1) |
| Watcher | The pistol teacher: a perched ranged target, shot diagonally | Escape Tunnel (1) |

No Shield and no Enforcer. There are no new enemy variants, because the district's new pressure is the unkillable eye and the Core. The only new body is the Collector Drone. The two data copies (`needle_dormant`, `needle_ledge`, D-097) change drops and aggro range, not behaviour.

**Boss test: the Collector Drone** (Collector Bay, D-064, D-079). A 400 HP card-deck boss scaled as the §42 "first mini-boss". Its Drop Press tracks Rook and locks where he stands, drawn in the eye's cone language, so it is the First Pursuit eye up close: stop and it lands on you. Tag Volley and Claw Dive check the dodge; Hook Sweep checks the sidestep. It drops the Service Pistol, which the next room teaches at once.

**§41 row**

| Introduce | Reinforce | Combine | Test |
|---|---|---|---|
| The eye: First Pursuit (it tracks along the ceiling and bolts a Rook who stops). The Core: Broken Lift FZ1 (it drains while you linger and refills on hits, at half drain and floored at 1, so it never burns; D-070, D-085) | The eye: the Collector's Drop Press, in the same cone language. The Core: Escape Tunnel FZ3, full drain on 48 px steps, **after the boss** | Escape Tunnel FZ3 again, after the boss: the Core with the new pistol (the Watcher) and two in-zone enemies to feed it | Collector Bay: the Collector Drone tests the **eye half only** (no Flow Zone). The Core is first tested under pressure in Lowlight |

**Conflict with §41, flagged (D-101):** the Undercity's combine beat plays after its boss, and the boss does not test the Core. Kept for a tutorial district's one-concept-at-a-time pacing; please confirm or overrule. The district is also a strict line with no loop or shortcut (D-102).

---

## 01 LOWLIGHT

**Mechanic thesis: *The Grid*** (D-071). Hit a breaker, beat the countdown, go low if you're late. A `Breaker` (player hits only, placed out of every grounded swing's reach, D-095) starts a `PowerShutter`'s clock. The shutter latches open once passed, and a late Rook goes low under its last 24 px slot as the panel drops. A safety sensor never lowers it onto a body. Security Station adds scanner beams on breaker circuits (D-072); the Rainline adds the Sweeper chase (D-073).

**Visual thesis: rain-slick neon over sodium streets.** The `lowlight.py` / `lowlight_style.py` palette: red, cyan, amber, green and violet neon on cold blue-violet night. The four new rooms add:
- Power Block: amber substations and a Transformer Core whose arcs run red while the grid is on security priority and cyan after the reroute.
- Security Station: cyan scanner lanes, white security light and red strobes around the Monitor Wall.
- Rainline Chase: the storm-lit elevated line toward the Bell Tower.
- Smuggler Route: the floodgate and the violet chalk-eye marks of the smugglers.

Landmarks: the Transformer Core, the Monitor Wall, the Rainline, the floodgate.

**Enemy ecosystem.** The existing Lowlight roster: Needle (rusher), Shield (frontal guard: go behind it or break the guard), Scout Drone (flier with a bolt), Hopper (pouncer), Watcher (perched sniper), and the Enforcer (the gold elite, Bell Tower). Batch 1 adds no variants: the new pressure is environmental (breakers, shutters, scanners, the Sweeper). The room specs place ranged enemies so they can be fought before a breaker's clock starts, never during it.

| New room | Enemies |
|---|---|
| Power Block | 2 Needle, Hopper, Scout Drone, Watcher |
| Security Station | Needle, Hopper, Scout Drone, Shield |
| Rainline Chase | 2 Needle (in the car wells; the Sweeper is the threat) |
| Smuggler Route | Needle, Hopper, Scout Drone, Shield |

**Boss test: Warden Krail's Grid Clamp.** Two high breakers in the Warden Tower arm a clamp over the centre. Dropping it on Krail is a poise-breaking environmental hit and a long punish window; a standing Rook under it loses a pip and is shoved out, a low Rook is safe, the same read as a shutter's slot (`GridClamp`, `data/level/clamp_krail.tres`). The arena teaches it: on arming, the clamp shows "Breakers live. Drop the clamp on him." once. The breakers are out of grounded reach, so the test is the Lowlight read of jump + air light on a breaker, then timing. Krail drops the Dash module.

**§41 row**

| Introduce | Reinforce | Combine | Test |
|---|---|---|---|
| Power Block L0: one breaker, one slow shutter | Power Block L1/L2 (the clock, a high breaker) and the Smuggler Route pump room | Power Block L3 (two shutters and a duct slot) and the Security Station roof (breaker + searchlight) | Warden Tower: the Grid Clamp on Krail |

---

## For the next district
- Write these four lines and the §41 row **before** building rooms, and give each room its own `tools/roomgen/<prefix>_<room>.py`.
- Check the economy first: the re-clear rule has 2 Scrap of headroom (K-49), so the next district needs sinks before respawning enemies.
- The §42 pacing estimate for Act I is in `M7_DISTRICT_REPORT.md` §3; measure it in the playtest before scaling (D-083).
