# ABI and client integration

The five JSON arrays in [abi/](abi/) are compiler-generated ABIs for GameRules, SeedLedger, Clans, Army, and Villages. Regenerate after `forge build` with `python3 tools/export_abi.py`; use `--check` to compare them with local artifacts. JSON amounts are integers. Convert game resources and SEED with `UNIT = 1_000_000`, not ETH decimals.

Use confirmed addresses from the deployment handoff. Wallet writes go to **Villages**, except public maintenance and the owner's SeedLedger timelock. These contracts provide no token transfer or allowance ABI.

## IDs

| Domain | Values |
| --- | --- |
| Resources | 0 Wood, 1 Food, 2 Stone, 3 Iron; Market input 4 means SEED |
| Fields / build targets | 0–1 forests, 2–3 farms, 4–5 quarries, 6–7 mines |
| Buildings | 0 Town Hall, 1 Walls, 2 Wheelhouse, 3 Storehouse, 4 Vault, 5 Burrow, 6 Barracks, 7 Academy, 8 Forge, 9 Clan Hall, 10 Market |
| Building build targets | Building ID + 8, hence 8–18 |
| Build slots | 0, 1 |
| Units | 0 Spearman, 1 Forager, 2 Shieldbearer, 3 Berserker, 4 Charger, 5 Catapult, 6 Scout |
| Movement modes | 1 raid, 2 scout, 3 outbound support, 4 return, 5 stationed support, 6 completed |
| Treasury kinds | 0 resource boost, 1 peace shield, 2 banner |
| Ranking categories | 0 construction spend, 1 research spend, 2 attack killed value, 3 defense killed value, 4 looted resources |
| Camp IDs | 0–199; camp slot = `50 * id + 49` |
| Tile coordinates | `x = tile % 100`, `y = tile / 100`, integer division |

## Player actions

| Villages method | Purpose / significant conditions |
| --- | --- |
| `found(name)` | One final, case-insensitively unique ASCII name per wallet; 3–16 letters/digits/underscores |
| `claimSeed()` | Claim all newly checkpointed SEED and award checkpoint XP; returns base SEED and base XP |
| `orderBuild(target, slot)` | Costs burned/debited immediately; NFT and Town Hall speed sampled now |
| `cancelBuild(slot)` | Owner's unfinished order only; before readyAt; 80% refund, capped resource storage |
| `orderResearch()` | Next tier, one pending study, Academy prerequisite |
| `exchange(input, output, lots)` | Each lot burns 100 input units, buys `25 + 5*(Market-1)` output units; cannot buy SEED |
| `treasury(kind, resource)` | Temporary resource boost, peace, or permanent banner |
| `train(unit, count)` | One training queue; reserves room immediately; cost and train time from GameRules |
| `allocateChampion(might, attack, defense, carry)` | Set cumulative allocations; each may only increase |
| `send(target, campId, units[7], champion, mode)` | Dispatch owned home troops; zero target explicitly selects a wild camp, not an unset deployment address |
| `recall(movementId)` | Return stationed support; callable by troop owner or supported village |
| `foundClan(name)` / `joinClan(id)` / `leaveClan()` | Membership gates; joining needs the founder's invitation; founder can leave only after other members |
| `inviteToClan(wallet, open)` | Founder invites (`true`) or withdraws an invitation (`false`); read `Clans.invited(villagesAddress, clanId, wallet)` |
| `raiseClanCapacity()` | Founder refreshes capacity after a Clan Hall upgrade |

No player action takes a source-wallet argument. The wallet's address is its identity for this season; it cannot rename or transfer its village. Contract wallets work through the same `msg.sender` rule. No EOA-only checks or `tx.origin` are used.

## Public maintenance

| Contract / method | Effect |
| --- | --- |
| SeedLedger `checkpoint()` | One successful observation per 04:00 UTC day |
| Villages `sync(wallet)` | Settle current production/upkeep for that village |
| Villages `completeBuild(wallet, slot)` | Apply ready upgrade, award construction points |
| Villages `completeResearch(wallet)` | Apply ready tier, award research points |
| Army `completeTraining(villagesAddress, wallet)` | Move the due queue into home troops |
| Army `resolve(villagesAddress, movementId)` | Resolve an arrived outbound or returning movement; both legs need resolution |
| Army `returnFormerSupport(villagesAddress, movementId)` | Return stationed troops whose owner and target no longer share a clan |

All completion calls fail before readiness and on duplicates. Zero-work checkpoints remain claimable once. Missing/failed external reads revert atomically; restoring the endpoint permits retry of the same unresolved action.

## Reads and events

- `Villages.village(wallet)` returns identity, tile, deadlines, building/field levels, tier, banner, and **last-settled** stock. `stock(wallet)` returns **current projected** stock including production/upkeep. `effectiveWalls(wallet)` includes passive repairs; `storageCapacity`, `vaultProtection`, and `roomCapacity` report current limits.
- `buildOrder(wallet, slot)` and `study(wallet)` report queue deadlines. Zero `readyAt` means no order. Completed orders are removed. `seedBalance(wallet)` forwards the canonical SEED balance.
- `Army.home(villagesAddress, wallet)`, `allocatedRoom`, `training`, `champion`, `championLevel`, and `championStats` provide the Army/Champion panels. `championStats` reads live NFT ownership and can revert if the NFT endpoint fails. XP and allocation state remain separately readable.
- `movement(villagesAddress, id)`, `movementCount`, and `supportMovements` provide movements. Completed movements keep metadata but clear troops/loot, preventing replay. Support emptied by combat immediately leaves the stationed list, releases its origin/target reservation and enters the usual return leg, emitting `MovementResolved`; resolving that empty return cannot change a replacement contingent. `report(villagesAddress, id)` provides battle powers, killed values, looted resources, decisive/cancelled flags, and resolution time. Scouting also emits `Scouted` with result and expiry. Village stock is public; scouting's gameplay benefit is the timed attack multiplier.
- `campParameters(id)` reports the current day's full defense and production rate. `camp(villagesAddress, id)` returns last-resolved camp storage; its last-stock and regrowth timestamps allow the UI to distinguish stored state from projected growth.
- `SeedLedger.observationCount()` and `observation(index)` provide the Squeektoshi/checkpoint history. `lastWork`, `lastCumulativeWork`, `currentDay`, and `account(villagesAddress, wallet)` expose checkpoint/claim state. Observation zero is the initial baseline, never a reward.
- `Clans.clanOf(villagesAddress, wallet)`, `clan`, and `sameClan` provide membership. `counters(villagesAddress, wallet, weekly, weekNumber)` returns raw counters, and `overall` returns the ranking score. Read `week()` for the current seven-day window.
- Name and tile lookup use `nameOwner(lowercaseNameHash)` and `tileOwner(tile)`. Lowercase only ASCII A–Z before hashing the name bytes. Enumerate `Founded` events to build rankings and map labels.

Filter helper events by their indexed `game` equal to the confirmed Villages address. Village `Founded`, construction/research events, `Exchanged`, `TreasuryUsed`, and Army `MovementSent`, `MovementResolved`, `Battle`, `Scouted` provide the indexable player history. Helpers intentionally support isolated caller namespaces; unrelated namespaces are not part of this season.

## Error handling

Named errors include `NoVillage`, `OnlyArmy`, `InsufficientResources`, `NotReady`, `InsufficientSeed`, `AlreadyCheckpointed`, `NoClaim`, `WorkDecreased`, `ExternalReadFailed`, `Unauthorized`, `TimelockPending`, and `Reentrancy`. Other prerequisite/limit failures now use the custom errors listed in [the revert migration table](ERRORS.md). An external read failure should be shown as an unavailable dependency, not a zero balance or zero work observation.
