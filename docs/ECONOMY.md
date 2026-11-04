# Economy and state transitions

## Arithmetic conventions

Resources and SEED use six decimal places (`UNIT = 1_000_000`); neither is an ERC token. XP, room, troops, battle powers, and killed-value points use integers. Costs and production geometric factors are multiplied then divided at each level in fixed point. Capacity adds each level's contribution. Burrow contributions round down to integer room individually. Durations are whole seconds; table growth floors the base duration, and applied speed/travel modifiers round up so fractional seconds cannot finish early. Resource accrual keeps fractional remainders between settlements.

The Core's `cumulativeWork` is an unsigned 64-bit physical-work counter. It is not an amount with ERC-20 decimals, a block count, or difficulty. All eight return words are checked for the documented widths and boolean encoding before the second word is used. Core reads have a named 200,000-gas allowance; NFT reads have 100,000 gas. Malformed, missing, reverting, and decreasing Core inputs fail without advancing observation or claim state.

## Time, checkpoints, and SEED

A game day is `floor((timestamp - 4 hours) / 1 day)` (clamped to zero before that epoch). Anyone may record one observation per day. The first observation baselines live cumulative work. Subsequent observations use `work = cumulativeWork - lastCumulativeWork`. Each adds `work * UNIT / 10` to the global SEED index and `min(150, floor(work/100))` to the checkpoint XP index. Zero work is a real observation, claimable once for zero reward.

Registration gives 1,500 SEED and sets the player's claim cursor to the latest observation. If the current day has no observation, founding records it before registration; this prevents a new village capturing a multi-day backlog. A village receives full observations recorded after its registration, not pro-rata intra-day rewards. Claims use index differences, with no loop over missed days, and move the cursor before returning. An account cannot claim twice, backdate its cursor, transfer SEED, or spend another canonical player's SEED. Construction cancellation refunds only part of a recorded cost.

If days pass without checkpointing, only an aggregated work difference is available from the approved read. It is attributed to the next actual observation. There are no fabricated individual-day deltas or multiplied rewards. The previous observed work signal persists for production until the next checkpoint. This sampling and the first-day baseline are deliberate operational choices; daily checkpointing by players gives the intended daily cadence.

Repointing Core rebaselines its counter when applied; accumulated uncheckpointed work on the old Core is not carried across different streams. Already-recorded rewards remain claimable. Operators should checkpoint the old Core before applying a change when that endpoint works. Changing only the NFT address does not rebaseline Core. A repoint to the same Core keeps the stored baseline unless the live counter now reads lower; then it rebaselines to the live value so checkpoints and founding resume after one 72-hour repoint (the decrease itself mints nothing).

## Founding and map

A wallet founds one final village: name 3–16 ASCII `[A-Za-z0-9_]`, case-insensitively unique; 750 of each resource; 1,500 SEED; Town Hall 1, Walls 1, and eight level-one fields. Founding grants a seven-day shield. Founding has no NFT requirement and cannot consume an existing wallet's identity.

There are 10,000 unique tiles. `7919` is coprime to 10,000, so `(7919 * slot + 1237) % 10000` is a permutation. Slots with `slot % 50 == 49` are the 200 camps, and the remaining 9,800 slots are assigned sequentially to villages. Coordinates are `(tile % 100, tile / 100)` with no wraparound. Placement never depends on a block hash, caller seed, or randomness service.

## Fields and buildings

For field level L: each field produces `18 * 1.4^(L-1)` per hour, costs its resource vector times `1.6^(L-1)`, and takes `0.4 * 1.4^(L-1)` hours. There are two fields for each resource.

| Field | Wood / Food / Stone / Iron base cost |
| --- | --- |
| Forest | 30 / 50 / 45 / 40 |
| Farm | 45 / 20 / 50 / 45 |
| Quarry | 45 / 45 / 20 / 50 |
| Mine | 50 / 45 / 45 / 10 |

Building costs use the **destination level** L. Default cost growth is 1.62; time is `0.6 * 1.45^(L-1)` hours.

| Building | Base resource cost | Overrides / SEED |
| --- | --- | --- |
| Town Hall | 180 / 170 / 180 / 170 | Cost growth 1.75; time `0.75 * 1.5^(L-1)` h; `667 * 1.5^(L-1)` SEED |
| Walls | 80 / 60 / 220 / 140 | Defaults |
| Wheelhouse | 100 / 110 / 90 / 100 | Cost growth 1.68; `300 * 1.5^(L-1)` SEED |
| Storehouse | 110 / 100 / 100 / 90 | Cost growth 1.28; time `0.45 * 1.2^(L-1)` h |
| Vault | 70 / 60 / 80 / 50 | Same growth/time as Storehouse; research tier 1 |
| Burrow | 70 / 110 / 70 / 50 | Cost growth 1.55; base time 0.5 h |
| Barracks | 150 / 150 / 130 / 170 | Defaults |
| Academy | 160 / 160 / 170 / 210 | Defaults |
| Forge | 130 / 110 / 140 / 260 | Research tier 2 |
| Clan Hall | 190 / 200 / 180 / 130 | Research tier 2 |
| Market | 150 / 200 / 150 / 150 | Defaults |

There is one building of each type and one level per specified field. Fields and ordinary buildings cap at 10 and current Town Hall level; Town Hall itself may upgrade to 10. Storehouse/Vault cap at 20 and twice Town Hall level. Existing buildings (including Town Hall/Walls) occupy plots, while fields do not. New pending buildings reserve plots. Available plots are `min(12, 3 + TH)`; there are eleven building types in this release. These rules resolve the brief's unspecified field-level cap and plot-counting convention.

Two construction slots permit two different targets concurrently; duplicate target upgrades cannot race. Costs are paid on order. The base duration is multiplied by `(1 - 0.03*(TH-1))`, then by

`1 - 0.30*(1 - 0.5^n)*min(1, lastWork/11000)`.

TH and NFT balance n are sampled at the order. NFT counts above the named precision bound 32 are equivalent at six-decimal precision. The NFT component never reduces time by more than 30%. TH contributes a separate maximum 27%, so their combined maximum reduction is 48.9%. A transferred NFT changes later orders immediately; it cannot rewrite the recorded deadline of an earlier order.

Completion is permissionless at or after readiness. Production accrues at the old level up to the completion transaction, then the new level starts. Delaying completion cannot retroactively produce more resources. Only the player can cancel, strictly before readiness, for 80% of original costs; storage may discard overflowing resource refunds. No completion or cancellation can replay. Only completed construction contributes ranking spend.

## Storage, output, upkeep, and treasury

At level L, sums run over levels 1 through L, and empty sums are zero:

- Per-resource storage: `1500 + sum(1800 * 1.22^(l-1))`.
- Per-resource Vault protection: `300 + sum(500 * 1.22^(l-1))`.
- Burrow room: `30 + sum(20*l * 1.12^(l-1))`.
- Upkeep: 0.5 Food per committed room per hour. Queued units reserve room and pay upkeep from ordering; home, deployed, returning, and supporting units remain charged to their originating village. Casualties release room only after old upkeep is settled.

All field output receives `1 + min(work/4320, 0.25 * WheelhouseLevel)`. SeedLedger stores the time integral of each Wheelhouse level's bonus at every work observation, allowing historical queries by binary search. A new work observation cannot rewrite prior production. A building upgrade settles output before changing its level.

A 500-SEED treasury purchase adds 25% to one resource's output for exactly 24 hours, multiplicatively with Wheelhouse. It cannot stack or overwrite an active boost. If settlement spans expiration, only the time before expiration gets the boost. A 4,000-SEED peace shield lasts 12 hours, at most once every three days; it is refused, without charge or cooldown, while a shield lasting at least as long (the founding shield or an earlier peace shield) is still running. A 1,000-SEED banner is a once-only cosmetic purchase.

Production is lazy net settlement: add time-weighted output, subtract Food upkeep over the interval, clamp Food at zero, then clamp each resource to storage. No food debt or starvation deaths are invented. Fractional resource remainders persist; overflow is discarded. This net-settlement convention also defines an interval in which production/upkeep rates cross between surplus and deficit. Claiming SEED does not produce resources. No gift, trade-with-another-village, or administrative credit operation exists for players.

Market exchanges burn 100 units of a selected resource or SEED for `25 + 5*(MarketLevel-1)` units of another resource. The output cannot be SEED or the same input resource. Trades that would exceed storage revert atomically, including any SEED burn. The named maximum is 1,000,000 lots per call; available balances/storage impose tighter practical limits.

## Research, training, and champion

Research is sequential tiers 1–5, one pending tier. Academy requirements are 1, 2, 4, 6, 8. Each costs `600*2.2^(tier-1)` resources split evenly, plus `300*2^(tier-1)` SEED, and takes `2*1.8^(tier-1)` hours. Research duration has no building-speed or NFT modifier. Completion grants its unlocks; no cancellation was specified for research or training.

| Tier | Unlocks |
| --- | --- |
| 1 | Forager, Vault |
| 2 | Shieldbearer, Berserker, Scout, Forge, Clan Hall |
| 3 | Charger, Logistics (+20% carry) |
| 4 | Catapult, Field Medicine (10% casualties returned, rounded down) |
| 5 | Logistics II (another +20% carry), Forced March (+20% speed) |

| Unit | Atk / Def / Speed / Carry / Room | Wood / Food / Stone / Iron | Minutes |
| --- | --- | --- | --- |
| Spearman | 40 / 35 / 6 / 50 / 1 | 50 / 45 / 45 / 40 | 15 |
| Forager | 20 / 15 / 8 / 120 / 1 | 55 / 55 / 30 / 20 | 12 |
| Shieldbearer | 15 / 70 / 5 / 20 / 1 | 60 / 45 / 70 / 45 | 18 |
| Berserker | 75 / 20 / 6 / 40 / 1 | 55 / 55 / 35 / 100 | 20 |
| Charger | 90 / 50 / 14 / 80 / 2 | 120 / 130 / 90 / 170 | 35 |
| Catapult | 30 / 10 / 3 / 0 / 4 | 320 / 140 / 300 / 170 | 70 |
| Scout | 0 / 5 / 16 / 0 / 1 | 30 / 40 / 20 / 40 | 8 |

Training time is unit minutes times count times `0.9^(Barracks-1)`. One queue reserves all requested room immediately; completion releases the queue into home troops without changing committed room. Troops cannot be dispatched twice or transferred by support. The named one-million-unit input bound is far above the maximum legal Burrow capacity and is exercised in isolated combat fuzz tests.

Champion level is `min(30, 1 + floor(sqrt(XP/100)))`. Level one begins with no allocated points; each gained level provides four, for a maximum of 116. Allocations only increase, with no respec. Might is `50 + 25*points`, attack/defense bonus is 0.5% per point (20 points each), and carry is 1% per point (20 points). The champion travels with at most one movement; support/scouting cannot include it.

XP is permanent killed resource value /20, rounded down, plus the per-checkpoint base XP described above. Holding at least one Squeek at award time multiplies XP by 1.1, rounded down. Existing XP is not erased on transfer. At battle/use time, current ownership multiplies Might and allocated stat bonuses by 1.1; the pre-NFT allocation caps still apply. Stats therefore lose that bonus immediately after a transfer. The arithmetic safety ceiling `MAX_XP = 1,000,000,000,000` is far above the level-30 threshold of 84,100 XP.

## Movements, scouting, and battle

Travel follows Euclidean distance without map wrapping, at the slowest dispatched unit's speed in tiles/hour. Distance uses fixed-point square root rounded up; travel time rounds up. Forced March divides time by 1.2. The outbound duration is saved for the return leg. At least one home troop is required; a champion cannot travel alone.

Outbound state becomes either stationed support or return on public resolution. Return begins at the resolution transaction's timestamp. Incoming battle uses the current garrison, current research/Forge/Walls, current protection/clan relation, and live champion NFT ownership; it is not backdated to the nominal arrival. This is a deterministic permissionless-resolution game, not an automatic scheduler. Transaction ordering between simultaneous attacks is observable and affects results.

Only scouts can make a scouting movement. The otherwise-unspecified scouting contest is deterministic: lose `min(sent scouts, defending home scouts)`; at least one survivor establishes a 12-hour scouting bonus for that attacker/target. These reconnaissance losses have no Field Medicine or combat-score awards. Scouts return; the target's resources are already public state. Only a still-live scouting bonus at raid resolution applies.

Attack is:

`(sum(unit attack) * (1 + 2%*Forge) * (1 + accompanying champion attack bonus) + accompanying Might) * scoutMultiplier`.

Defense is:

`(home defense * (1 + 2%*Forge) + allied support defense with each origin's Forge + home champion Might) * (1 + home champion defense bonus) * (1 + 4%*Walls) + 40*TH`.

An away champion contributes no home defense. Each side loses `min(1, 0.5*enemyPower/ownPower)`, rounded up **once for the whole army**: each unit type loses the floor of its share, and the army's rounded-up total is completed one unit at a time from the types with the largest fractional parts (lowest index on ties). A one-unit stack therefore survives a raid whose casualty rate is far below one unit per stack; each stationed support contingent is a separate army. Zero attack loses the attacking troops (subject to non-wipe Field Medicine); it never loots a zero-defense camp. Decisive positive attack at least twice defense wipes defending troops; this wipe takes precedence over Field Medicine. Otherwise research tier 4 returns `floor(10% of rounded casualties)` immediately. Killed-value counters and XP use permanent losses after medicine.

Only decisive attacks loot and damage Walls. Carry uses surviving troops and additive Logistics/champion bonuses. Divide carry equally over four resources and take each quarter only from stock above that resource's Vault protection; unused quarters are not redistributed. SEED is never part of loot. For targets with `target TH + 3 <= attacker TH`, halve carry before splitting and award no combat points or combat XP to either side. Loot counters still record actual resources taken.

Each twenty surviving Catapults inflict one Wall level of damage, at most two per battle. Damage cannot exceed built Walls. Damaged levels repair automatically at one per 12 hours; a further raid preserves an already-running repair schedule. Wall damage is temporary; built level is unchanged.

Defender resources are removed at battle and placed in that movement's loot. Return adds them to the attacker's then-current storage; overflow is discarded. No path credits the same loot twice. Losing a battle or encountering a new shield/clan relation still produces a return leg. All survivors and the champion become available only after return resolution.

## Clans, camps, and ranking

Clan Hall 1 permits joining a clan whose founder has invited the wallet (`Villages.inviteToClan(wallet, true)`; `false` withdraws the invitation); joining consumes the invitation, so a member who leaves needs a new one. Level 3 permits founding. Names are 3–24 ASCII identifier characters, case-insensitively unique. Capacity starts at `3 * founder Hall level`, maximum 30; the founder can refresh it after upgrading. The founder leaves last; an emptied clan is dissolved and its name stays reserved. There are no clan resource accounts, gifts, dues, kicks, or ownership transfer; the founder's control over membership is admission by invitation.

Only clanmates may support. One contingent per origin/target pair may be outbound or stationed; up to 30 stationed contingents are bounded in storage. Support cannot include a champion or loot. The origin pays its upkeep and loses its room on casualties. The target gets defense points/XP for the aggregate defense; supporter kills are not counted again. Departed clanmates immediately stop contributing defense, and anyone may send that former support home. The origin or host can recall still-allied support. After battle losses, an emptied contingent is automatically removed from the stationed list, releases its origin/host reservation, and begins the same return leg as recalled support. Its origin may send fresh support immediately; completing the empty return neither creates troops nor changes the new reservation. Becoming clanmates while an attack is in flight cancels combat; because joining needs the founder's invitation, a target cannot impose this on an attacker's clan.

Camp ID modulo three selects size 0.6, 1, or 1.5. Season day zero is the 04:00 UTC day containing deployment. Full defense is `size * min(4000, 150 + 40*day)`. The 60% Shieldbearer /40% Spearman mix is represented as virtual fractional garrison strength: average defense 56 and resource cost 204 per weighted unit. This preserves the specified exact defense even when it cannot be expressed in whole player units. Partial combat removes attack/2 defense; a decisive attack clears it. Killed equivalent value is removed defense *204/56, rounded down.

The first damaging raid starts a 24-hour regrowth deadline; later raids, including raids on an empty camp, cannot postpone it. At the first resolution after that deadline, defense restores to the current day's full amount. Stock grows at `size*(20 + 2*day)` per resource per hour, integrates each 04:00 UTC rate transition, and caps at 24 hours of the current rate. Camps have no Vault/Walls, never attack, and have the same per-attacker three-raids/day limits. Depleted camps can be raided for newly grown stock before defense regrows.

Construction and research counters accumulate completed resource+SEED spend in subunits; divide each counter by `100*UNIT` for its ranking points. Attack/defense counters store permanent killed resource value in whole units. Loot stores resource subunits. Overall is exactly:

`build + research + min(build, (attack + defense)/200)`.

Season counters never reset. Weekly counters are separately stored under the seven-day index from Clans deployment. Completion/settlement time chooses the counter's week. Cancellation farming cannot generate points; support cannot double count kills. Rankings are sortable client-side from canonical player events and these counters.
