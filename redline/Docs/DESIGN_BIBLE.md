# REDLINE — Master Game Design Bible & Claude Code Build Specification

**Version:** 0.1 Pre-Production
**Platform:** Steam / PC first
**Recommended engine:** Godot 4.x
**Genre:** High-speed 2D pixel-art action platformer + exploration + light Metroidvania + score attack
**Working title:** REDLINE
**North star:** **Movement is life. Violence buys time. Curiosity reveals the truth.**

> Source of truth for Claude Code. Do not build everything at once. First build movement/combat foundations and one production-quality vertical slice.

---

# 1. HIGH CONCEPT

REDLINE is a high-speed 2D action adventure inside **Veyra**, a vertical megacity powered by the mysterious **Pulse**. The protagonist, **Rook** (working name), survives an execution attempt with an illegal **Redline Core** implanted in their chest. In hostile Pulse-saturated areas it burns energy continuously, but can steal residual Pulse from defeated enemies, machines, destruction and high-skill movement.

**Keep moving. Fight aggressively. Steal time. Explore the city. Discover why you were erased.**

The game alternates explosive action with exploration, NPC encounters, shops, secrets, movement puzzles, bosses and cinematic story. Reactor drain pauses in safe exploration zones.

# 2. DESIGN PILLARS

1. Movement is the primary toy; an empty room must already be fun.
2. Easy to start, deep to master.
3. Controlled speed: exploration gives breathing room between Flow Zones.
4. Expression over raw stats.
5. Discovery matters: secrets, shortcuts, NPCs, lore, challenges and ability gates.
6. Spectacle with readability.
7. Story through play.
8. Fast recovery from failure.
9. No required grinding.
10. Handcrafted campaign rooms and bosses.

# 3. INSPIRATION RULES

Study principles, never copy assets, characters, maps, silhouettes or lore.

- **Hollow Knight:** interconnected exploration, distinct regions, ability-gated revisiting, map discovery, NPCs, environmental storytelling and flexible builds.
- **Katana ZERO:** responsiveness, handcrafted action rooms, environmental kills, fast retries and cinematic storytelling.
- **SANABI:** traversal that doubles as combat expression and cinematic pixel presentation.
- **Nine Sols:** readable telegraphs, mastery combat and bosses that test learned systems.

# 4. CORE LOOP

**Explore → encounter → Flow → move/fight → steal charge → earn Scrap → secret/shortcut → Anchor → upgrade/build → NPC/quest → route → boss → traversal ability → revisit old regions.**

Targets: short loop 10–60 sec; room 1–5 min; mission 10–25 min; district 1.5–3 hr. First playthrough target ~15–22 hours.

# 5. MOVEMENT

Initial: run, jump, variable jump, crouch, slide, ledge assist, dodge, melee, ranged, interact.

Unlocks: **Dash, Air Dash, Wall Jump, Wall Run, Grapple, Enemy Bounce, Ground Slam, Rail Grind, Recoil Launch, Phase Dash, Pulse Tether, Overdrive.**

Feel tech: coyote time, jump/input buffers, acceleration/deceleration, air control, apex gravity, corner correction, ledge forgiveness, dash buffering, momentum preservation and sensible cancels. All tuning values are external data/resources.

Optional expert tech: slide jump, dash cancel, grapple-release boost, wall-run kick, recoil boost, enemy pogo, slam cancel, rail launch, perfect-dodge boost.

# 6. REDLINE CORE

**Normal:** drain only in Flow/combat sectors; kills, movement feats and Pulse objects refill; Anchors stabilize.
**Story/Assist:** slower drain, larger refill, optional reduced boss damage.
**Redline Challenge:** faster drain, tighter recovery, score multiplier and leaderboard eligibility.

Charge sources: kills, elites, executions, perfect dodges, parries, environmental kills, combos, Pulse machinery, Flow Gates and traversal lines. Critical state uses heartbeat/percussion, HUD pulse and subtle vignette without obscuring play.

# 7. HEALTH / DEATH / CHECKPOINTS

Player has health, reactor charge and limited healing injectors. Early attacks are forgiving. **Anchors** save, refill, stabilize, permit loadout changes and later fast travel.

Death: near-instant restart; permanent progress retained; standard mode drops recoverable unbanked Scrap; accessibility can disable loss. Boss runbacks stay short.

# 8. COMBAT

Inputs: light, heavy/context, ranged, dodge/dash, jump, grapple, heal, interact.

Attack data: damage, stagger, knockback, hitstop, startup/active/recovery, hitbox, cancels, aerial behavior, reactor gain, style, status and launch vector.

Defense: generous Dodge → optional Perfect Dodge rewards → later Parry. Parry is useful but not mandatory for most content.

Launched enemies can collide, smash doors/glass, trigger mines, strike hazards and fall.

# 9. WEAPONS

**Melee:** Pulse Blade, Split Katars, Gravity Hammer, Chain Scythe, Shock Spear, Reactor Fists, Saw Cleaver, Phase Staff.
**Ranged:** Service Pistol, Scattergun, Burst SMG, Heavy Revolver, Rail Lance, Arc Cannon, Rocket Tube, Cryo Projector, Ricochet Pistol, Pulse Bow.
**Experimental:** Gravity Gun, Teleport Spike, Enemy Launcher, Black-Hole Seed, Saw Disc, Drone Hive, Time Fracture Gun, Magnet Cannon.

Each has normal/alternate actions, aerial use, movement interaction, mastery challenge and **Power / Flow / Utility** upgrade branches.

# 10. STYLE / COMBO

Reward attack variety, movement transitions, environmental kills, perfect dodges, parries, aerial kills, multi-kills, enemy collisions, no-hit rooms and momentum. Repetition gives diminishing style.

Ranks: **D → C → B → A → S → SS → SSS → REDLINE**. Rewards can include Scrap, charge, medals, cosmetics and leaderboard score; style never blocks story.

# 11. CIRCUITS

Limited **Core Capacity** supports build-changing Circuits. Examples: Momentum Coil, Glass Pulse, Rebound, Scavenger, Blood Capacitor, Static Trail, Magnetic Rounds, Emergency Loop, Ghost Step, Predator, Demolitionist, Longline, Clean Circuit, Overheat, Kinetic Battery, Ricochet Heart, Execution Protocol, Groundwire, Last Second, Twin Pulse, Runner's Debt.

Target: **60–80 Circuits**, at least 20 build-defining, with saved loadouts.

# 12. PROGRESSION / ECONOMY

Permanent categories: **Traversal, Combat, Core, Knowledge**.

Currencies: **Scrap** (common), **Core Shards** (major upgrades), **Memory Fragments** (story/endings), **Mastery Tokens** (challenges/advanced techniques). Avoid currency bloat.

# 13. HUB / SHOPS

Hub: **The Relay**, an abandoned transit interchange that becomes a resistance settlement.

- **Mara — Mechanic:** weapons/core.
- **Nix — Cartographer:** maps/pins/transit/hints.
- **Vell — Circuit Broker:** Circuits/capacity/loadouts.
- **Iko — Black Market:** experimental optional stock.
- **Sera — Archivist:** memories/translations/scenes.
- **Bramm — Trainer:** movement/mastery/practice.
- **Luma — Medic:** healing and rescue questline.
- **Orr — Radio Operator:** rumors/quests/world updates.

The Relay visibly evolves with repaired lights, music layers, rescued NPCs, conversations, trophies and routes. Essential progression is never randomized.

# 14. WORLD MAP

```text
                         [08 REDLINE SPIRE]
                                |
                   [07 MACHINE CROWN]
                    /             \
             [06 WARFRONT]     [05 SKYLINE]
                  |                |
             [04 DEAD METRO]---[03 BIOVAULT]
                    \            /
                     [02 IRONWORKS]
                           |
                      [01 LOWLIGHT]
                           |
                         [RELAY]
                           |
                      [00 UNDERCITY]
```

Final graph needs loops, cross-connections, elevators, transit, shortcuts and late-game gates.

# 15. DISTRICTS / LEVELS

Target: 8 major districts, ~8–10 major sequences each, ~70–80 principal sequences plus side rooms, secrets, challenges and bosses.

**00 UNDERCITY:** Wake; Medical Ruin; Maintenance Shaft; First Pursuit; Broken Lift; Escape Tunnel; Relay. Boss: Collector Drone. Gentle onboarding.

**01 LOWLIGHT:** Flooded Alley; Market Run; Apartment Stack; Neon Roofs; Power Block; Security Station; Rainline Chase; Smuggler Route; Bell Tower; Warden Tower. Boss: **Warden Krail**. Unlock: **Dash**.

**02 IRONWORKS:** Intake; Conveyor Maze; Foundry Floor; Crane Hall; Furnace Climb; Assembly Line; Scrap Canyon; Pressure Works; Foreman's Route; Core Forge. Boss: **The Foreman**. Unlock: **Wall Jump/Wall Run**.

**03 BIOVAULT:** Quarantine Gate; Glass Garden; Nursery; Spore Tunnels; Specimen Wing; Flooded Lab; Living Lift; Genome Archive; Escape Habitat; Heart Chamber. Boss: **Mother Bloom**. Unlock: **Grapple**.

**04 DEAD METRO:** Closed Platform; Service Tunnel; Ghost Train; Switching Yard; Flood Line; Express Run; Carriage War; Signal Tower; Last Platform; Terminal Zero. Boss: **Conductor-9**. Unlock: **Rail Grind**.

**05 SKYLINE:** Vertical Gardens; Corporate Atrium; Skybridge; Drone Port; Hotel Exterior; Broadcast Tower; Airship Dock; Storm Run; Penthouse Siege; Cloud Gate. Boss: **Astra Vale**. Unlock: **Air Dash**.

**06 WARFRONT:** Breach; Trench Street; Evacuation Block; Artillery Avenue; Broken Hospital; Siege Tower; Tank Graveyard; Resistance Line; Command Bunker; No-Man's Roof. Boss: **General Voss / Siege Engine**. Unlock: **Phase Dash**.

**07 MACHINE CROWN:** Data Aqueduct; Gravity Well; Cooling Spine; Mirror Factory; Logic Maze; Pulse Reservoir; Inverted City; Clock Chamber; Root Network; Crown Gate. Boss: **The Architect**. Unlock: **Pulse Tether/Overdrive precursor**.

**08 REDLINE SPIRE:** False Lobby; Memory Elevator; Broken Timeline; Hunter Hall; City Above City; Core Descent; First Memory; Pursuit Reversed; Redline Ascent; The Choice. Finale changes with story state.

Optional postgame: **The Null**, remixed high-skill challenge space.

# 16. ENEMIES

Modular AI: perception + locomotion + attack + defense + reactions + faction.

Early: Watcher, Needle, Shield, Hopper, Scout Drone.
Industrial: Riveter, Furnace Guard, Loader, Saw Drone, Welder.
Biovault: Sporeling, Stalker, Bloom Guard, Leech, Mimic Husk.
Metro: Rail Hound, Signal Drone, Tunnel Sniper, Carriage Brute, Static Shade.
Skyline: Wing Guard, Lancer Drone, Corporate Hunter, Shield Pair, Storm Unit.
Warfront: Rifle Unit, Grenadier, Heavy Gunner, Combat Medic, Walker, Hunter Mine, Officer.
Machine Crown: Mirror Unit, Phase Guard, Gravity Orb, Repair Swarm, Null Knight, Logic Turret.

Target: **45–60 normal variants + 12–16 elites**, minimal lazy palette swaps. Include enemy journal.

# 17. BOSSES

Major: Collector Drone; Warden Krail; The Foreman; Mother Bloom; Conductor-9; Astra Vale; General Voss/Siege Engine; The Architect; story-dependent finale.

Optional: Glass Saint, Scrap King, Twin Couriers, Hollow Engine, Sleeper, Prototype R-0, Null Beast, Old Warden, Memory of Rook.

Rules: nearby checkpoint, skippable repeated intros, readable telegraphs, meaningful phases, no cheap offscreen hits, fast restart, accessibility scaling.

# 18. STORY BIBLE

Veyra publicly claims the **Pulse** is limitless clean energy. The truth: the network stores fragments of human neural activity. The city learned that intense human experience creates unusually stable Pulse signatures and eventually harvested memory and emotion at industrial scale.

Rook was part of **Project REDLINE**, an attempt to create a human able to interface directly with the Pulse without losing identity. The project apparently failed. Rook's memories were fragmented and distributed through the city. The implanted core is partly powered by **Rook's own missing memories**.

The reactor has a darker meaning: survival may consume traces of real human experience.

## Central mysteries

1. Who ordered Rook's execution?
2. Why can Rook absorb Pulse?
3. What caused the original Redline disaster?
4. Is the Pulse conscious, or an accumulation of memories?
5. Why does The Architect know Rook by another name?
6. Did the resistance tell the truth?
7. Can Veyra survive without Pulse?

## Acts

**Act I — Run:** survive, reach Relay, assume the city authority is the enemy.
**Act II — Hunt:** recover memories and discover Project REDLINE.
**Act III — Doubt:** learn resistance leaders also exploited Pulse research.
**Act IV — Remember:** recover Rook's role in the disaster.
**Act V — Choose:** determine the future of Pulse and Veyra.

## Endings

- **Sever:** destroy the network; release stored memories but destabilize Veyra.
- **Crown:** control the network and stabilize Veyra at the cost of becoming its central intelligence.
- **Release:** difficult ending requiring memories and NPC quest states; transform the network.
- **Redline:** hidden ending involving Project REDLINE and The Null.

No simplistic morality meter. Consequences are shown through people and world state.

# 19. NPC / QUEST SYSTEM

NPCs support state, relationship flags, quest stages, conditional dialogue and world consequences. Prefer dialogue, map notes, radio rumors and environmental clues over giant objective markers.

Quest types: rescue; investigation; traversal challenge; duel; delivery with changing route; hidden-room discovery; elite hunt; defense; memory reconstruction; multi-district character arc; meaningful choice.

Avoid filler such as "kill 20 identical enemies." Side quests should reveal character/world, alter the hub, unlock mechanics/cosmetics, create memorable encounters or affect endings.

# 20. MAP / EXPLORATION

Player begins with incomplete map knowledge. Nix provides base maps; exploration fills detail.

Features: fog of discovery, player pins, vendor pins, Anchor markers, transit, discovered bosses, unresolved gate symbols, optional secret hints and late-game district completion statistics. Knowledge upgrades may indicate that something remains undiscovered without giving exact coordinates.

# 21. SECRETS / COLLECTIBLES

Every district includes hidden rooms, alternate routes, breakable walls, traversal secrets, lore terminals, Memory Fragments, Core Shards, cosmetics, challenge gates, optional NPCs and secret-boss clues.

Collectibles: Memory Fragments, lost recordings, posters, weapon schematics, music tracks, skins, Pulse echoes and journal entries. Do not fill the map with meaningless icons.

# 22. PUZZLES / INTERACTIVITY

Puzzles stay compatible with movement: momentum routing, timed switches, redirected projectiles, grapple geometry, moving machinery, power rerouting, gravity, enemy positioning and environmental observation. Main-path puzzles are readable; optional puzzles can be difficult.

Interactive world: breakable windows, doors, lights, signs, terminals, vending machines, hanging objects, explosive pipes, crates, furniture, alarms, elevators, train controls, shutters and environmental weapons. Prefer authored destruction states over expensive full simulation.

# 23. DIFFICULTY CURVE

**Opening 30 min:** one concept at a time, low density, generous health, long telegraphs, frequent checkpoints. First boss builds confidence.

**Hours 1–4:** dash, ranged combinations, environmental kills, optional challenges.

**Midgame:** combine enemy roles, increase verticality, introduce parry and advanced traversal without universal mandatory precision.

**Late game:** demand system combinations rather than obscure tricks.

**Endgame:** main finale remains beatable by an ordinary player who learned the game; The Null, mastery challenges and REDLINE ranks serve experts.

Optional adaptive assistance may suggest settings after repeated deaths but never silently changes difficulty.

# 24. ACCESSIBILITY / QOL

Full rebinding; controller glyph switching; vibration slider; screen-shake slider; flash reduction; hitstop intensity; high-contrast modes; subtitle size/background/speaker labels; colorblind-safe indicators; hold/toggle options; aim assist; reactor assistance; damage assistance; currency-loss toggle; map hint strength; cinematic skip; pause during dialogue; generous checkpoints; scalable UI; separate audio sliders.

Accessibility settings never shame the player.

# 25. ART DIRECTION / GRAPHICS

## Identity

**Neo-gothic pixel cyberpunk**, not generic neon cyberpunk.

Blend decaying monumental architecture, industrial machinery, analog technology, brutalist mass, cathedral-like vertical spaces, restrained neon, organic Pulse growth, rain, steam, sparks and strong silhouettes. Veyra must feel old, layered and inhabited.

## Pixel specification

Prototype at an internal reference canvas around **426×240 or 480×270**, then validate camera/readability before locking. Rook target: roughly **32–48 px tall** depending on camera tests.

Rules:

- deliberate pixel clusters;
- region-specific palettes;
- strong silhouettes;
- integer scaling where practical;
- high-resolution UI may overlay pixel gameplay;
- no arbitrary mixing of pixel densities.

## Character animation

Rook needs: idle, run, sprint, turn, jump rise/apex/fall, land, hard land, slide, crouch, wall contact/run, dash, air dash, grapple cast/pull/swing/release, melee chains, heavies, ranged recoil, hurt, knockback, heal, execute, interact, death and cinematic poses.

Use anticipation, smear frames, squash/stretch, silhouette change, trails, impact frames, controlled hitstop, directional debris and afterimages.

## Environment

Each district gets unique palette, architecture, foreground set, midground, multiple parallax layers, particles, weather, breakables, lighting language and signage.

2D lights are accents, not a replacement for authored pixel shading. Gameplay remains readable without bloom.

# 26. VFX / CAMERA / GAME FEEL

VFX vocabulary: slash arcs, impact sparks, dust, rain, steam, debris, electricity, Pulse particles, glass shards, speed lines, afterimages, explosion silhouettes and shockwaves.

Camera: movement look-ahead, soft dead zone, speed-sensitive framing, boss framing, landing impulse, hit impulse, configurable shake and rare dramatic zoom. Never create constant nausea.

# 27. UI / UX

Minimal moving HUD: health, reactor, healing, weapon, optional combo/style and contextual interaction.

Menus: inventory/loadout, Circuits, weapon upgrades, map, journal, quests/rumors, collectibles/lore, settings/accessibility.

Visual language: industrial CRT/transit signage fused with Pulse artifacts. Fast transitions and controller-first navigation.

# 28. AUDIO / MUSIC

Dynamic states: exploration, tension, Flow, critical reactor, boss and aftermath. Districts have distinct instrumentation but recurring motifs. Relay theme gains instruments as the settlement grows.

Prioritize readable audio for jump/land, dash, perfect dodge, parry, low reactor, enemy telegraphs, hit confirmation, secrets and Anchor activation. Music must not remain at maximum intensity constantly.

# 29. SAVE / STEAM / CHALLENGES

Multiple profiles + autosave. Save story flags, NPC states, inventory, weapons, Circuits, currencies, map, shortcuts, bosses, collectibles, settings and statistics. Use versioned schemas, migrations, atomic writes and backups.

Plan for Steam achievements, cloud saves, controller support, challenge leaderboards, optional ghosts and rich presence where worthwhile. Core gameplay must remain independent of Steam APIs.

Ghost modes: personal best, developer ghost, and leaderboard ghost if technically viable. Challenge types: no-hit, time trial, movement-only, weapon mastery, survival, style target, reactor endurance and boss rematch. Include optional speedrun timer and fast reset.

# 30. REPLAYABILITY / CONTENT TARGETS

Postgame: boss rematches, challenge ranks, The Null, NG+, optional enemy remix, advanced Circuit builds, mastery, secrets/endings and speedrun tools. NG+ adds remix value rather than only enemy HP.

Aspirational targets after vertical-slice validation:

- 8 major districts + prologue/endgame;
- ~70–80 principal sequences;
- 45–60 normal enemy variants;
- 12–16 elites;
- 9 major bosses;
- 6–10 optional bosses;
- 20–26 weapons;
- 60–80 Circuits;
- 30–50 meaningful quests/character events;
- 100+ worthwhile secrets/discoveries;
- 4 endings.

Quality outranks hitting a numeric target.

# 31. GODOT TECHNICAL ARCHITECTURE

```text
res://
  autoload/
    Game.gd
    SaveManager.gd
    AudioManager.gd
    SceneRouter.gd
    EventBus.gd
    Settings.gd
  player/
    controller/
    states/
    combat/
    abilities/
    animation/
  enemies/
    base/
    behaviors/
    variants/
    elites/
  bosses/
  weapons/
  circuits/
  interactables/
  world/
    districts/
    rooms/
    transitions/
    anchors/
    hazards/
  quests/
  dialogue/
  ui/
  audio/
  vfx/
  data/
  tests/
  devtools/
```

Prefer composition/state machines over giant inheritance trees. Data-driven Resources: `PlayerMovementConfig`, `WeaponData`, `AttackData`, `EnemyData`, `CircuitData`, `UpgradeData`, `QuestData`, `DialogueData`, `LootTable`, `DistrictData`, `AccessibilityConfig`.

Use explicit signals/events. Do not turn EventBus into an untyped dumping ground.

# 32. ENEMY AI ARCHITECTURE

Example state flow: Idle → Patrol → Suspicious → Engage → Position/Attack → Recover → Stagger → Dead.

Composable modules: sensing, ground/flying movement, pathing, attack selection, preferred range, group spacing, retreat, shield, status and hit reaction.

An **Encounter Director** controls activation and simultaneous attackers so early fights remain readable. No machine-learning AI is needed.

# 33. PERFORMANCE

Target smooth **60+ FPS** on ordinary Steam gaming hardware. Pool frequent projectiles/particles where useful; avoid hot-path allocations; cache references; disable expensive offscreen systems; use simple collision; cap debris; avoid excessive dynamic lights; profile before optimizing.

# 34. INTERNAL DEVELOPMENT TOOLS

Build tools before mass content:

- room metadata editor;
- spawn markers;
- Flow Zone boundaries;
- Anchor placement;
- camera zones;
- hazard paths;
- traversal validation;
- collectible tracker;
- quest/dialogue validator;
- broken-reference scanner;
- save-state inspector;
- weapon/enemy debug panels;
- hitbox visualization;
- performance overlay;
- quick boss restart;
- teleport-to-room;
- unlock-all debug profile.

# 35. TESTING

Automate where practical: save serialization, upgrade math, Circuit capacity, damage/status math, quest transitions, inventory persistence and data validation.

Gameplay QA: controller latency, keyboard parity, aspect ratios, low-FPS behavior, checkpoint recovery, sequence breaking, softlocks, rebinding, accessibility, boss restart and save migration.

# 36. PRODUCTION MILESTONES

## M0 — Foundation

Godot project, Git, folder architecture, conventions, input map, settings, debug scene, save skeleton and test skeleton. No mass content.

## M1 — Movement Lab

Graybox room. Perfect run/jump/slide/dodge/dash feel. Camera, controller support and metrics overlay. Do not proceed until movement alone is enjoyable.

## M2 — Combat Lab

Pulse Blade, pistol, Scattergun; three enemies; damage/stagger/launch; hitstop; placeholder VFX; reactor prototype; style prototype.

## M3 — Vertical Slice

One polished Lowlight route (~15–25 min), Relay mini-hub, 5–7 enemies, 3–5 weapons, 8–12 Circuits, one quest, secrets and Warden Krail boss. This establishes production-quality art/audio.

## M4 — Validation

Playtest and measure deaths, completion time, confusion, favorite mechanics, control complaints and performance. Change design before scaling.

## M5 — World Framework

Map, fast travel, quests, NPC state, shops, economy, journal, collectibles and save migration.

## M6 — Content Pipeline

Editor/dev tools, reusable enemy modules, room templates, art pipeline and validation.

## M7 — District Production

Build regions in batches. Every district requires a mechanic thesis, visual thesis, enemy ecosystem and boss test.

## M8 — Narrative Integration

Cinematics, memory scenes, NPC arcs, endings and world-state changes.

## M9 — Endgame / Steam / Accessibility

Achievements, leaderboards/ghosts where viable, NG+, The Null, settings, localization readiness and demo flow.

## M10 — Polish

Performance, bugs, animation, audio, balance, onboarding, controller/Steam Deck validation and release candidate.

# 37. CLAUDE CODE RULES

1. Read this document before implementation.
2. Do not implement future milestones unless requested.
3. Never hardcode content that belongs in Resources/data.
4. Keep scripts focused; avoid god classes.
5. Every major system gets debug visibility.
6. Comment design intent, not obvious syntax.
7. Keep gameplay independent of Steam APIs.
8. Preserve keyboard/controller parity.
9. Document every new dependency.
10. Do not mass-generate final assets before vertical-slice approval.
11. Placeholder art is expected during M0–M2.
12. Commit in small logical units.
13. Maintain `Docs/DECISIONS.md`, `Docs/CHANGELOG.md`, `Docs/TODO.md`, `Docs/KNOWN_ISSUES.md`.
14. If implementation conflicts with this bible, flag the conflict instead of silently changing design.

# 38. FIRST CLAUDE CODE TASK — START HERE

**Do not start by making 80 levels.**

Build M0 and M1 only:

1. Initialize Godot 4 project.
2. Create repository structure from this specification.
3. Configure keyboard + controller actions.
4. Implement a data-driven player movement state machine.
5. Build graybox Movement Lab.
6. Implement run, jump, variable jump, coyote time, jump buffer, slide and dodge.
7. Add camera look-ahead/dead-zone and configurable shake framework.
8. Add live debug overlay: velocity, grounded state, movement state and FPS.
9. Put movement tuning into `PlayerMovementConfig`.
10. Add reset hotkey and spawn markers.
11. Add basic tests/data validation where practical.
12. Produce `M1_MOVEMENT_REPORT.md` with controls, tuning, issues and experiments.
13. **STOP after M1 for human playtesting. Do not begin combat automatically.**

## M1 acceptance criteria

- keyboard and controller responsive;
- jump buffer/coyote time reliable;
- slide transitions reliable;
- no random geometry sticking;
- camera does not fight player;
- restart instant;
- tuning does not require editing controller logic;
- stable 60 FPS in lab;
- moving for several minutes is fun without enemies.

# 39. ART ASSET MASTER LIST

## Player

Rook sprite sheet; movement animations; combat animations; weapon overlays; afterimage masks; damage/heal/execution effects; portraits; cinematic poses.

## Enemies

Unique silhouette sheets per archetype; attack anticipation; hurt/stagger/death; elite markers; district-specific effects.

## Environment

Tilesets, modular architecture, floors/walls/platforms, doors, windows, ladders/rails, props, furniture, signs, terminals, pipes, machinery, breakables, foreground silhouettes, backgrounds, parallax layers and weather.

## VFX

Impacts, slash arcs, bullets, trails, explosions, smoke, dust, rain, steam, electricity, Pulse, glass, debris, shields, status effects, healing, reactor critical, boss phase transitions and secrets.

## UI

HUD, map symbols, menus, icons, Circuit cards, weapon icons, currency icons, shop UI, dialogue boxes, journal, quest UI, settings, accessibility and controller glyphs.

## Narrative

NPC portraits/sprites, memory-scene assets, story props, faction symbols, posters, documents, boss intros and ending scenes.

# 40. ART PIPELINE

Before final asset production, create an **Art Bible** containing:

- reference canvas;
- pixel density;
- sprite scale;
- palette philosophy;
- outline rules;
- shading rules;
- lighting rules;
- animation FPS ranges;
- smear-frame rules;
- VFX resolution;
- parallax conventions;
- naming/export conventions.

Every generated or commissioned asset must be checked against the Art Bible. AI-generated imagery may be useful for ideation/reference, but final game assets need consistency, cleanup, animation compatibility and clear commercial rights.

# 41. LEVEL DESIGN RULES

Every major sequence should contain:

1. a readable entrance;
2. a movement opportunity;
3. an encounter or traversal thesis;
4. at least one optional curiosity hook;
5. a memorable visual landmark;
6. recovery/breathing space when needed;
7. an exit that naturally points forward.

Every district should introduce a mechanic safely, reinforce it, combine it, then test it in the boss.

Avoid repeated rectangular combat boxes. Use vertical routes, chase rooms, moving trains, collapsing spaces, open traversal, compact interiors and environmental combat.

# 42. ONBOARDING PLAN

First 5 minutes: move, jump, interact, simple attack.
5–15: dodge, first enemy compositions, first secret.
15–30: reactor introduced safely, first Anchor, first NPC, first mini-boss.
30–60: Relay, first shop/map choices, Lowlight begins.
~60–90: player earns Dash and understands the central loop.

Tutorial text should be short and contextual. Whenever possible, teach through room geometry and enemy placement.

# 43. WHAT MAKES REDLINE DISTINCT

REDLINE is **not** "Hollow Knight with guns" and not "Katana ZERO with a map."

Its identity is the interaction of:

- high-speed expressive movement;
- reactor pressure in authored Flow Zones;
- interconnected city exploration;
- enemy/environment launching;
- destruction;
- build-changing Circuits;
- a mystery where the player's survival resource is tied to stolen memory;
- districts designed around movement fantasies;
- accessible campaign + very high optional mastery ceiling.

# 44. VERTICAL-SLICE SUCCESS TEST

Do not scale production unless external playtesters independently report most of the following:

- movement feels immediately satisfying;
- they understand what the reactor wants them to do;
- they want to replay rooms more stylishly;
- combat is readable;
- they remember at least one enemy;
- they are curious about Veyra/Rook;
- they found or noticed secrets;
- they can explain the basic build system;
- first boss feels fair;
- they want to continue after the slice.

If these fail, fix the core instead of producing more content.

# 45. FINAL PRODUCT VISION

The desired player journey is:

**Minute 1:** "This controls really well."
**Minute 10:** "I can do cool things already."
**Hour 1:** "I want to know what happened here."
**Hour 3:** "I found my own route/build."
**Hour 8:** "I move completely differently now."
**Finale:** "The mechanic I used to survive means something to the story."
**Postgame:** "I want to master this."

That is the standard REDLINE should aim for.
