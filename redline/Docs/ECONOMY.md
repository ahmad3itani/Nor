# REDLINE Economy (M5)

Bible §12: "Scrap (common), Core Shards (major upgrades), Memory Fragments (story/endings), Mastery Tokens (challenges). **Avoid currency bloat.**" The slice uses Scrap, Core Shards and Memory Fragments. Mastery Tokens wait for challenges (M9).

All numbers below come from `progression/EconomyAudit.gd`, which reads the room scenes and data, so they can't drift. `tests/unit/test_economy.gd` enforces the targets.

## Scrap: sources (one thorough first run)

| Source | Scrap |
|---|---|
| Enemies, each placed enemy killed once (29) | 176 |
| Warden Krail | 150 |
| Quest rewards (Dead Air 120, Chart Lowlight 100) | 220 |
| Breakable-wall stashes (4 secrets) | 200 |
| Scrap stashes in secret spots (4) | 180 |
| **Total** | **926** |

Scavenger (+50% Scrap) raises everything that drops as pickups.

## Scrap: sinks (all shop stock at list price)

| Shop | Stock |
|---|---|
| Vell: 10 Circuits (Emergency Loop after Dead Air) | 850 |
| Mara: Split Katars 150, Heavy Revolver 180, Spare Injector 200 | 530 |
| Nix: Lowlight base map 40, Transit pass 60, Surveyor's lens 90 | 190 |
| **Total** | **1,570** |

## Targets (tested)

| Rule | Target | Now |
|---|---|---|
| A thorough first run affords a real share of the stock, but not all of it, so purchases are choices | 45–85% | **59%** |
| The essentials (Nix's base map + transit pass, 100 Scrap) are affordable from early income | ≥ 100 from enemies and stashes | 356 |
| Enemies respawn on every room visit, so farming exists but exploring pays better: one full re-clear | ≤ 15% of stock (235) | 176 |

**M5 finding:** before this pass, a first run covered only **35%** of the stock (546 Scrap), because secrets paid nothing. Walls now hold Scrap, and four secret spots carry stashes. Stashes are the loot inside secrets and don't count as extra secrets.

## Other currencies
- **Core Shards** (3): each adds +1 Circuit capacity (4 → 7). Never sold.
- **Memory Fragments** (3): story and lore only. Never spent.
- **Death:** unbanked Scrap drops as one recoverable cache (bible §7, D-031). Settings can turn loss off.

## Changing prices
Prices live in `data/circuits/*.tres` (`price`) and `data/shops/*.tres` (`ShopItem.price`), and drops in `data/enemies/*.tres` (`scrap_drop`). After any change, run `--filter=economy`. The test prints the full breakdown.
