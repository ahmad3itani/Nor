# REDLINE Economy (M5, audited in M7, NG+ in M9, upgrades in the expansion)

Bible §12: "Scrap (common), Core Shards (major upgrades), Memory Fragments (story/endings), Mastery Tokens (challenges). **Avoid currency bloat.**" The slice uses Scrap, Core Shards and Memory Fragments. Mastery Tokens wait for challenges (M9).

All numbers below come from `progression/EconomyAudit.gd`, which reads the room scenes and data, so they can't drift. `tests/unit/test_economy.gd` enforces the targets.

## Scrap: sources (one thorough first run)

Audited in M7 (D5b) with all eleven new rooms merged: Undercity and the full Lowlight.

| Source | Scrap |
|---|---|
| Enemies, each placed enemy killed once (59 that pay Scrap: 14 in the Undercity for 71 and 45 in Lowlight for 261; the dormant Medical Ruin Needle drops nothing) | 332 |
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

## Scrap: sinks (all shop stock at list price, plus upgrades)

| Sink | Stock |
|---|---|
| Vell: 10 Circuits (Emergency Loop after Dead Air) | 850 |
| Iko: Bootleg Injector 260, Hot Wire 150, Live Current 120, Slipstream 130 | 660 |
| Mara: Split Katars 150, Heavy Revolver 180, Spare Injector 200 | 530 |
| Nix: Lowlight base map 40, Transit pass 60, Surveyor's lens 90 | 190 |
| Mara's workbench: upgrades (below) | 810 |
| Vell's Core work: Capacity Lattice I | 240 |
| **Total** | **3,280** |

### Upgrades (expansion Phase 1, D-182, D-187)

Upgrade tiers live in `data/upgrades/*.tres` (`UpgradeData`, one `UpgradeTier` per step). `EconomyAudit` counts every tier bought with Scrap at its price, **one** price per Mk III branch group (the highest of the three, since only one can be bought) and **nothing** for a granted tier. All Phase-1 tiers are Act I.

| Upgrade (station) | Tier | Price | Needs |
|---|---|---|---|
| Pulse Blade (workbench) | Mk II: hold heavy to charge, damage +10% | 110 | `met_mara` |
| Split Katars (workbench) | Mk II: the same | 110 | `met_mara` |
| Service Pistol (workbench) | Mk II: +2 rounds, reload ×0.85 | 70 | `met_mara` |
| Scattergun (workbench) | Mk II: +1 shell, spread ×0.85 | 100 | `met_mara` |
| Heavy Revolver (workbench) | Mk II: +1 round, reload ×0.85 | 110 | `met_mara` |
| Dash Coil (workbench) | I: dash cooldown ×0.80 | 120 | the Dash |
| Evade Servo (workbench) | I: perfect window +0.02 s, dodge cooldown ×0.9 | 80 | `met_mara` |
| Injector Rework (workbench) | I: heal time ×0.75 | 110 | `met_mara` |
| Surge Coupling (workbench) | I: the Pulse Surge | 160, **granted** | Mara installs it after Krail (D-218) |
| Capacity Lattice (Vell) | I: Core capacity +1 | 240 | 3 Core Shards, `met_vell` |
| **Stock** | | **1,210** | **1,050** counted as sinks |

- **Rebranch** (repair 2): swapping an owned Mk III branch at the workbench costs `UpgradeData.rebranch_price` (40). It is repeatable, so the audit reports it under `repeatable_sinks` and keeps it out of the bands and the re-clear cap. No Phase-1 upgrade has a branch yet.
- **Capacity** (D-186): Act I maximum 4 + 5 shards + Lattice I = 10 of the catalog's 21 Circuit cost (48 %, inside the CIRCUITS.md 40–50 % band).
- **Schematics** (D-184) are never spent and carry no Scrap: `EconomyAudit.tally` skips them.

### Per act and pending districts (D-187)

Each district's act comes from `DistrictTheme.act` (default 1), quests from `QuestData.act`, shop stock from `ShopItem.act` and upgrade tiers from `UpgradeTier.act` (0 = the upgrade's `act`). The audit reports `sinks_by_act`, `one_time_by_act` and `per_clear_by_act`, and `test_act_cumulative_bands` applies the flat rules below to every finished act counted with all earlier acts (acts 2+ also alone), so later stock never hides an over-generous Act I.

A district still being built sets `economy_final = false` in its theme. Its rooms, and every quest, shop item and upgrade tier of an act with no final district yet, go to `pending` only, until its economy merge flips the flag (`compute(false, true)` audits them anyway). Today every district is final and everything is Act I.

**Known limit:** NPC dialogue `give_scrap` is always booked to Act I, because `NpcProfile` and `DialogueData` carry no act. Today all dialogue Scrap is Act I, so the bands are exact; when Act II NPCs (Ironworks) give Scrap, derive the act (an `NpcProfile.act`, or the district of the NPC's room) before trusting the per-act bands.

## Targets (tested)

| Rule | Target | Now |
|---|---|---|
| A thorough first run affords a real share of the stock, but not all of it, so purchases are choices | 45–85% | **54.0%** (1,772 / 3,280) |
| The essentials (Nix's base map + transit pass, 100 Scrap) are affordable from early income | ≥ 100 from enemies and stashes | 892 |
| Enemies respawn on every room visit, so farming exists but exploring pays better: one full re-clear | ≤ 15% of stock (492) | **332** (headroom 160) |
| K-49 guard: re-clear headroom | ≥ 150 | **160** |
| Every finished act, cumulative | the two rules above | Act I: 54.0 %, 332 / 492 |

`test_economy` also pins the Undercity row above (`test_undercity_income_as_audited`), checks that the district rows add up to the totals, and pins the PW1 numbers (sinks 3,280, one-time 1,772, re-clear 332).

The audit's full output after the upgrade Phase 1:

```json
{"boss":230,"bundles":560,"by_district":{"lowlight":{"act":1,"boss":150,"bundles":380,"enemies_first_clear":261,"one_time":1141,"per_clear":261,"walls":350},"relay":{"act":1,"boss":0,"bundles":0,"enemies_first_clear":0,"one_time":0,"per_clear":0,"walls":0},"undercity":{"act":1,"boss":80,"bundles":180,"enemies_first_clear":71,"one_time":381,"per_clear":71,"walls":50}},"coverage":0.540243902439024,"dialogue":0,"enemies_first_clear":332,"final_acts":[1],"ng_secret_bundles":0,"one_time":1772,"one_time_by_act":{"1":1772},"pending":{"boss":0,"bundles":0,"districts":[],"enemies_first_clear":0,"quests":0,"sinks":0,"walls":0},"per_clear":332,"per_clear_by_act":{"1":332},"quests":250,"repeatable_sinks":{},"sink_items":{"shop_iko":660,"shop_mara":530,"shop_nix":190,"shop_vell":850,"upgrades_luma":0,"upgrades_vell":240,"upgrades_workbench":810},"sinks":3280,"sinks_by_act":{"1":3280},"upgrade_sinks":1050,"walls":400}
```

**M5 finding:** before this pass, a first run covered only **35%** of the stock (546 Scrap), because secrets paid nothing. Walls now hold Scrap, and four secret spots carry stashes. Stashes are the loot inside secrets and don't count as extra secrets.

**M7 finding (D5b): no trim was needed.** The rooms landed on the planned numbers (one-time ≈ 1,771, re-clear ≈ 332), and every rule passes. Iko's stock (+660) is what keeps the re-clear rule passing: without it the cap would be 235. The re-clear was then only **2 Scrap under its cap** (K-49). The planned remedies, in order:
1. The Medical Ruin Needle must stay `needle_dormant.tres` (drops 0). This is done and tested.
2. Remove First Pursuit's pair-2 Needle (x 3200) and keep the Hopper at 3320: saves 5. (Not needed; the Needle stays.)
3. After that, raise sinks (new stock in a later district) or flag it in DECISIONS rather than cut more enemies.

**Expansion finding (PW1, D-187): K-49 is closed by remedy 3.** The Act I upgrade stock adds 1,050 Scrap of sinks (Surge I is granted, D-218), so the cap rises from 334 to 492 and the re-clear sits **160 Scrap** under it (`test_k49_headroom` keeps at least 150). Coverage drops from 79 % to 54.0 %: a thorough first run now affords about half of all stock, a real choice between upgrades and Circuits.

If coverage ever passes 85%, halve the Undercity stashes (180 → 90) first, then lower the Collector's drop to 60.

## NG+ and remix (M9)

NG+ (D-153) keeps weapons, Circuits, shop upgrades, upgrade tiers (`upg_*`, D-182), schematics (`sch_*`, D-184), banked Scrap and found Core Shards, and starts the world over. `compute(true)` is unchanged in meaning: upgrades carry, so they add no NG+ income. `EconomyAudit.compute(true)` is the NG+ audit: the remix applied to every room (`RemixLibrary.apply`), plain stashes counted as taken, secret stashes refilled at `NgPlusConfig.secret_scrap_scale` = **0.25** (`data/ngplus/ng_plus.tres`, R09.2).

| Source | First run `compute(false)` | NG+ with remix `compute(true)` |
|---|---|---|
| Enemies, first clear | 332 | 332 |
| Bosses | 230 | 230 |
| Quests | 250 | 250 |
| Wall stashes | 400 | 400 |
| Scrap stashes | 560 | 122 (secret stashes × 0.25) |
| **One-time** | **1,772** | **1,334** |
| One full re-clear | 332 | 332 |
| Stock coverage (sinks 3,280) | 54.0% | 40.7% |

By district in NG+: Undercity 227 one-time (26 in stashes), Lowlight 857 (96 in stashes), the Relay 0.

**The remix Scrap rule** (T09 R09.11): remix EnemyData files have `scrap_drop = 0`, but a SET or SWAP replacement spawns with the replaced enemy's drop, and only ADDed enemies drop nothing. So remix on pays exactly what remix off pays (the enemy rows above are identical), and the K-49 re-clear headroom is untouched. `RemixRules` RM-1..RM-8 lint the ops; `test_economy` checks both audits. Carried Scrap and kits mean an NG+ player can already buy most stock; the refill only keeps secrets worth finding.

Challenges, the Deep Rig and the Pulse Pit pay no Scrap and grant nothing (their enemies are Scrap-free `*_null` / kit states in a sandbox, D-147); medals and records are the reward (D-148). Mastery Tokens (§12) are still not built.

## Other currencies
- **Core Shards** (5): each adds +1 Circuit capacity (4 → 9; Vell's Capacity Lattice I adds one more for Scrap once 3 are found, D-186). Shards are never sold. Three are Dash revisits (`cs_alley_dash`, `cs_smuggler_dash`, `cs_uc_tunnel_dash`), so capacity before Krail is at most 6. See `CIRCUITS.md`.
- **Memory Fragments** (5: `mf_undercity_01`, `mf_lowlight_01`..`04`): story and lore only. Never spent. Since M8 each recovered fragment unlocks its memory vignette (played at an Anchor or from the journal); it is still never spent, and remembering pays nothing (D-112).
- **NPC arcs** (M8) are economy-neutral: arc dialogue carries no `give_*` (validator), so the re-clear headroom is untouched (D-122).
- **Schematics** (7, D-184): key items that unlock upgrade tiers (`sch_<id>`). Never spent, never stacked, not secrets, and no achievement, quest or count metric reads them.
- **Death:** unbanked Scrap drops as one recoverable cache (bible §7, D-031). Settings can turn loss off.

## Changing prices
Prices live in `data/circuits/*.tres` (`price`), `data/shops/*.tres` (`ShopItem.price`) and `data/upgrades/*.tres` (`UpgradeTier.price`), and drops in `data/enemies/*.tres` (`scrap_drop`). After any change, run `--filter=economy`. The test prints the full breakdown.
