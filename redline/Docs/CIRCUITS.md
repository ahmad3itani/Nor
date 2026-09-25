# Circuits (bible §11)

Circuits are build-changing chips slotted into Rook's Core. The bible targets 60–80 in the full game. The M3 slice shipped **12**, covering the main build directions: momentum, glass cannon, defense, economy, sustain and precision. M7 adds Iko's three black-market Circuits, for **15** in the catalog.

## Rules
- **Core Capacity:** 4 at the start (`ItemCatalog.base_core_capacity`), **+1 per Core Shard**. The world has **5** shards, so the maximum is **9** (M7, D-082).

  | Shard | Where | Needs |
  |---|---|---|
  | `cs_market` | Market Run, the stash behind the cracked wall | nothing |
  | `cs_roofs` | Neon Roofs, the high route | dodge-jump |
  | `cs_alley_dash` | Flooded Alley, the Dash shelf near the start | Dash |
  | `cs_smuggler_dash` | Smuggler Route | Dash |
  | `cs_uc_tunnel_dash` | Escape Tunnel, the shard ledge (Undercity revisit) | Dash |

  So capacity is at most 6 before Krail and 9 after the Dash revisits.
- **Equipping:** only at an **Anchor** (the loadout opens after you rest). Equipping is free and instant; the constraint is capacity, not currency.
- **Sources:**
  - **Vell's shop** (Scrap);
  - Vell's intro gift (**Scavenger**);
  - the **Dead Air** reward (**Longline**);
  - **Iko's shop** (Scrap): Hot Wire, Live Current and Slipstream, next to the Bootleg Injector.
  
  **Emergency Loop** appears in the shop only after Dead Air is done.

## The 15

| Circuit | Cost | Price | Effect | Stats |
|---|---|---|---|---|
| Momentum Coil | 2 | 90 | Melee hits deal up to +40% damage, scaling with your speed when you swing | `momentum_damage` +0.4 |
| Glass Pulse | 2 | 110 | All your damage +35%; damage you take is doubled | `melee_damage` ×1.35, `ranged_damage` ×1.35, `damage_taken` ×2 |
| Rebound | 1 | 60 | A perfect dodge instantly reloads your ranged weapon | `perfect_dodge_reload` +1 |
| Scavenger | 1 | 40 | Scrap from every source +50% | `scrap_gain` ×1.5 |
| Blood Capacitor | 2 | 100 | Every 4 kills restores 1 health pip | `kills_per_heal` 4 |
| Ghost Step | 1 | 70 | Dodge/dash i-frames last 40% longer; perfect-dodge window +0.05 s | `iframe_time` ×1.4, `perfect_window_bonus` +0.05 |
| Predator | 2 | 90 | +50% damage against staggered or launched enemies | `predator_damage` +0.5 |
| Demolitionist | 1 | 60 | Launched-body impacts, wall slams and breakable walls take double damage | `environmental_damage` ×2 |
| Emergency Loop | 2 | 120 | Once per rest, a lethal hit leaves you at 1 pip instead | `emergency_loop` +1 |
| Longline | 1 | 50 | Ranged shots travel 50% farther | `ranged_range` ×1.5 |
| Clean Circuit | 1 | 70 | At full health, everything refills the Core 30% more | `full_health_reactor_bonus` +0.3 |
| Runner's Debt | 1 | 80 | The Core drains 40% slower above run speed, 40% faster standing still | `runners_debt` 0.4 |
| Hot Wire (Iko) | 2 | 150 | Overclocked rounds: ranged shots hit 50% harder but reach 30% less | `ranged_damage` ×1.5, `ranged_range` ×0.7 |
| Live Current (Iko) | 1 | 120 | Spikes, walls and clamps deal 2.5× damage for you; your melee deals 15% less | `environmental_damage` ×2.5, `melee_damage` ×0.85 |
| Slipstream (Iko) | 1 | 130 | Dodge/dash i-frames last 20% longer; the Core drains 25% slower above run speed, 25% faster standing still | `iframe_time` ×1.2, `runners_debt` +0.25 |

All costs, prices and numbers live in `data/circuits/*.tres`.

## Budget (M7, D-082: confirmed)
The 15 Circuits cost **21** capacity together. At the full 9, Rook slots about 43% of that (4 of 21 at the start, 6 before Krail). Before M7 it was 7 of 17 (41%). So the two extra shards keep pace with Iko's three new Circuits instead of loosening the build choice: even a complete run still has to leave out more than half of the catalog, and the Circuits that cost 2 (six of the 15, Hot Wire among them) still compete for space. No price or cost changed. The five shards are counted by the Core Shard table above. Adding a shard or a Circuit should keep capacity at roughly 40–50% of the catalog's total cost.

## How it works (for developers)
- `CircuitData` is declarative. `multipliers` **multiply** across all equipped Circuits (default 1.0), and `values` **add up** (default 0.0). Gameplay code never checks which Circuit is equipped. It asks for a stat:
  ```gdscript
  hit.damage_mult = Game.circuit_mult(&"environmental_damage")
  if Game.circuit_value(&"perfect_dodge_reload") > 0.0: ...
  ```
- Stat names must be listed in `CircuitData.KNOWN_STATS`, and data validation (`test_circuits_shops`) fails on a typo.
- **Where each stat is read:**

| Stat | Consumer |
|---|---|
| `melee_damage`, `momentum_damage`, `predator_damage` | `PlayerCombat` (melee hit build) |
| `ranged_damage`, `ranged_range` | `PlayerCombat` (projectile spawn) |
| `damage_taken`, `emergency_loop`, `kills_per_heal`, `perfect_dodge_reload`, `perfect_window_bonus` | `PlayerCombat` |
| `iframe_time` | `DodgeState`, `DashState` |
| `environmental_damage` | `Enemy` (impacts, slams), `BreakableWall` |
| `full_health_reactor_bonus`, `runners_debt` | `ReactorCore` |
| `scrap_gain` | `Game.scrap_multiplier()` |

## Adding a Circuit
1. Create `data/circuits/<id>.tres` (`CircuitData`) with a cost, price, description and stats.
2. If it needs a new stat, add the name to `KNOWN_STATS` and read it where the behavior lives, with a comment giving the design intent.
3. Add it to `data/catalog.tres` and to a shop, reward or pickup.
4. Run the tests: catalog validation catches missing ids, unknown stats and circuits that have no effect.
