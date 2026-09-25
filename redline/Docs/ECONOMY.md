# REDLINE Economy (M5, audited in M7)

Bible §12: "Scrap (common), Core Shards (major upgrades), Memory Fragments (story/endings), Mastery Tokens (challenges). **Avoid currency bloat.**" The slice uses Scrap, Core Shards and Memory Fragments. Mastery Tokens wait for challenges (M9).

All numbers below come from `progression/EconomyAudit.gd`, which reads the room scenes and data, so they can't drift. `tests/unit/test_economy.gd` enforces the targets.

## Scrap: sources (one thorough first run)

Audited in M7 (D5b) with all eleven new rooms merged: Undercity and the full Lowlight.

| Source | Scrap |
|---|---|
| Enemies, each placed enemy killed once (62, plus the dormant Medical Ruin Needle, which drops nothing) | 332 |
| Bosses: Warden Krail 150, Collector Drone 80 (one-time, counted by `EnemyData.boss`) | 230 |
| Quest rewards (Dead Air 120, Chart Lowlight 100, The Way Up 30) | 250 |
| Breakable-wall stashes (10 walls) | 400 |
| Scrap stashes in secret spots (16) | 560 |
| **Total** | **1,772** |

Chart Lowlight pays when `map_charted_lowlight` is set, which happens at 50% of Lowlight's map cells (`world_map.tres` `district_thresholds`, M7 D8b). Standing on every surface of every Lowlight room reveals 63.0%, so the chart asks for about 0.79 of everything a player can see. The Undercity charts at 40% (standable 61.8%). The plain critical path reveals 44% of it, so walking it charts the district. No quest pays for that chart. `test_world_map::test_thresholds_match_standable_coverage` keeps each value within [0.6, 0.85] × standable coverage.

Scavenger (+50% Scrap) raises everything that drops as pickups.

### By district (`by_district` in the audit)

| District | Stashes | Walls | Enemies (first clear = one re-clear) | Boss | One-time |
|---|---|---|---|---|---|
| Undercity (7 rooms) | 180 | 50 | 71 | 80 | 381 |
| Lowlight (10 rooms) | 380 | 350 | 261 | 150 | 1,141 |
| Relay | 0 | 0 | 0 | 0 | 0 |

The Undercity pays mostly through exploration, as an onboarding district should: stashes on the Wake sill (10) and walkway (15), the Medical Ruin shelf (20), the Maintenance Shaft closet (30) and crew locker (20), the First Pursuit cache (30 + a 20 wall), the Broken Lift car roof (15), the Collector Bay vent (40) and the Escape Tunnel panel (a 30 wall). Its enemies: Medical Ruin 15, Maintenance Shaft 22, First Pursuit 15, Broken Lift 5, Escape Tunnel 14.

**Enemy data variants and Scrap:** `needle_dormant.tres` (the Medical Ruin practice Needle) drops **0**, so a re-clear of the first armed room pays nothing for it. `needle_ledge.tres` (Broken Lift) changes only the aggro range (D-097) and keeps the Needle's 5. A new variant that changes `scrap_drop` changes the re-clear total, so run `--filter=economy`.

## Scrap: sinks (all shop stock at list price)

| Shop | Stock |
|---|---|
| Vell: 10 Circuits (Emergency Loop after Dead Air) | 850 |
| Iko: Bootleg Injector 260, Hot Wire 150, Live Current 120, Slipstream 130 | 660 |
| Mara: Split Katars 150, Heavy Revolver 180, Spare Injector 200 | 530 |
| Nix: Lowlight base map 40, Transit pass 60, Surveyor's lens 90 | 190 |
| **Total** | **2,230** |

## Targets (tested)

| Rule | Target | Now |
|---|---|---|
| A thorough first run affords a real share of the stock, but not all of it, so purchases are choices | 45–85% | **79%** (1,772 / 2,230) |
| The essentials (Nix's base map + transit pass, 100 Scrap) are affordable from early income | ≥ 100 from enemies and stashes | 892 |
| Enemies respawn on every room visit, so farming exists but exploring pays better: one full re-clear | ≤ 15% of stock (334) | **332** |

`test_economy` also pins the Undercity row above (`test_undercity_income_as_audited`) and checks that the district rows add up to the totals.

The audit's full output after D5b:

```json
{"boss":230,"bundles":560,"by_district":{"lowlight":{"boss":150,"bundles":380,"enemies_first_clear":261,"one_time":1141,"per_clear":261,"walls":350},"relay":{"boss":0,"bundles":0,"enemies_first_clear":0,"one_time":0,"per_clear":0,"walls":0},"undercity":{"boss":80,"bundles":180,"enemies_first_clear":71,"one_time":381,"per_clear":71,"walls":50}},"coverage":0.794618834080718,"dialogue":0,"enemies_first_clear":332,"one_time":1772,"per_clear":332,"quests":250,"sink_items":{"shop_iko":660,"shop_mara":530,"shop_nix":190,"shop_vell":850},"sinks":2230,"walls":400}
```

**M5 finding:** before this pass, a first run covered only **35%** of the stock (546 Scrap), because secrets paid nothing. Walls now hold Scrap, and four secret spots carry stashes. Stashes are the loot inside secrets and don't count as extra secrets.

**M7 finding (D5b): no trim was needed.** The rooms landed on the planned numbers (one-time ≈ 1,771, re-clear ≈ 332), and every rule passes. Iko's stock (+660) is what keeps the re-clear rule passing: without it the cap would be 235. The re-clear is now only **2 Scrap under its cap**, so any new respawning enemy on the map fails the rule. The planned remedies, in order:
1. The Medical Ruin Needle must stay `needle_dormant.tres` (drops 0). This is done and tested.
2. Remove First Pursuit's pair-2 Needle (x 3200) and keep the Hopper at 3320: saves 5.
3. After that, raise sinks (new stock in a later district) or flag it in DECISIONS rather than cut more enemies.

If coverage ever passes 85%, halve the Undercity stashes (180 → 90) first, then lower the Collector's drop to 60.

## Other currencies
- **Core Shards** (5): each adds +1 Circuit capacity (4 → 9). Never sold. Three are Dash revisits (`cs_alley_dash`, `cs_smuggler_dash`, `cs_uc_tunnel_dash`), so capacity before Krail is at most 6. See `CIRCUITS.md`.
- **Memory Fragments** (5: `mf_undercity_01`, `mf_lowlight_01`..`04`): story and lore only. Never spent.
- **Death:** unbanked Scrap drops as one recoverable cache (bible §7, D-031). Settings can turn loss off.

## Changing prices
Prices live in `data/circuits/*.tres` (`price`) and `data/shops/*.tres` (`ShopItem.price`), and drops in `data/enemies/*.tres` (`scrap_drop`). After any change, run `--filter=economy`. The test prints the full breakdown.
