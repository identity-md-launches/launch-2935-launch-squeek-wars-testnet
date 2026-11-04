# Security review handoff

This is the implementing contributor's adversarial review and test map. It is **not** an independent audit, an admission decision, or a signed deployment artifact. The workflow's independent contributor must review accepted source and the actual generated manifest before release. No deployment or attestation was performed here.

## Authorization and state boundaries

| Surface | Authority and isolation |
| --- | --- |
| Village founding/actions | `msg.sender` is the player. One permanent village/name per wallet. No action permits arbitrary source wallets. |
| SEED | SeedLedger accounts, minted, and net burned amounts are scoped to the calling game. Canonical registration/claim/burn/refund comes from Villages only. No transfer/approval method exists. |
| Army and champion | Commands use `worlds[msg.sender]`. The canonical world is Villages. Passing another wallet to a helper from an attacker address creates/accesses only the attacker's unrelated world. |
| Public movement resolution | Explicit game address selects an already-authorized movement, not a new action. Due-time/state checks and transition to return/completed prevent replay. |
| Village accounting callbacks | Only the immutable Army may debit, credit, loot, settle upkeep, damage Walls, or record combat points. Army derives callback targets from its authenticated world. |
| Clans and rankings | Caller-scoped membership/counters. Villages gates Clan Hall levels and passes the real player. Direct helper calls cannot affect canonical rankings. |
| Owner | Only SeedLedger has an owner, passed explicitly by constructor. Its entire authority is propose/apply/cancel the 72-hour external-read repoint, or permanently renounce. No owner game mutation, pause, upgrade, rule setter, or rescue exists. |

The namespace design is essential: frontend reads and logs must pin the confirmed Villages address. A helper's callable accounting method is not an externally authorized write to the canonical world. Tests exercise direct calls against counterfeit namespaces and confirm canonical balances, XP, troops, and counters remain unchanged.

Constructors make no external calls, do not inspect dependency bytecode, do not create child contracts, and accept no dynamic arguments or deployment value. The manifest must supply the same Rules/Ledger/Clans graph to Army and Villages. Wrong but nonzero internal dependencies are a concrete manifest error, not a post-launch owner setting.

## Custody and value flow

There is no payable function, receive/fallback, token receiver, token approval/transfer, withdrawal, beneficiary, fee, pool, or prize. The game is virtual-resource accounting. The EVM can force ETH or unsolicited token balances onto an arbitrary address; these contracts provide no mechanism to use or recover them, and clients must not send assets.

Permitted resource changes are founding grants, local production, own costs/refunds, own Market output, and loot. Support carries no resources. Cross-village resource debits exist only in Army's decisive battle path; the movement stores exactly what the defender lost and can credit it once on return. Both ends clamp storage; overflow is destroyed. SEED never enters that path. The invariant handler snapshots other players around non-loot actions to detect unintended cross-village changes, and separate battle tests reconcile defender debits and carried loot.

All reserved troops remain in their origin's room total across home/queue/outbound/support/return states. Losses settle prior upkeep before releasing room. Completion clears training; return clears troops and loot. The stateful invariant recomputes every player's total room from all these locations after randomized actions.

## External calls and liveness

Only the approved Core `state()` and NFT `balanceOf(address)` are external data dependencies. Calls use `STATICCALL`, bounded gas, exact return lengths, and canonical ABI-width validation. Production math and claims never accept a caller-supplied work value or seed. Core decreases revert; a timelocked replacement baselines its new counter without minting old history.

Reentrancy guards cover mutation entry points that call modules or external readers. The remaining ungated helper mutations have no external calls and operate only in the caller's namespace. Test readers attempt callbacks under static context, and a malicious test world attempts to resolve a battle recursively; neither succeeds.

A broken or incompatible Core blocks new observations and first registration; recorded claims remain available unless their XP award needs an unavailable NFT read. A broken NFT can block new build quotes and champion/XP-sensitive settlement. These failures are atomic and retryable. There is no silent fallback to guessed work or holdings. The only repair authority is the 72-hour timelock; renouncing it makes dependency breakage irreparable through these contracts. This is an explicit trust and availability assumption.

An upstream contract can itself be upgradeable or report false work. These contracts validate encoding and monotonicity, not the physical truth of the hamster's work. The owner can select another compatible reader after the public delay. This power can change rewards and availability and must be assessed as part of the manifest/launch authority review.

## Determinism, arithmetic, and bounded work

- No block hash, randomness, caller-selected random seed, signature service, or external scheduler is used. Fixed placement is a bijection over all 10,000 tiles.
- Building/field levels, research, unit types, plots, troop room, queue counts, and support-list length are bounded. Geometric loops run at most 20 levels; support loops run at most 30 contingents. Claims are constant-time, and historical Wheelhouse queries are logarithmic in actual checkpoints.
- Resource/SEED multiplications use uint256 with six-decimal units; Core's 64-bit bound and maximum game levels are far below arithmetic limits. Input troop count is at most one million, and canonical Burrow capacity is much lower. Combat fuzzing checks up to one million troops against an independent casualty calculation at maximum levels.
- NFT counts are bounded before shifting; the 30% build reduction is tested at arbitrary counts and work values. Champion XP and level have named caps.
- Timestamp casts assume normal EVM timestamps below uint64's limit. Consensus timestamp/ordering affects deadlines and arrival ordering, as it does in other timestamp-based games; no asset-valued randomness is inferred from it.
- There are no delegate calls, external linked libraries, initialization routes, self-destruction, or packed hashes of adjacent dynamic values. The runtime opcode scan follows the supplied protected floor and is exercised on all five deployed applications.

## Issues found and repaired during implementation

1. **Stale checkpoint before founding:** without a current-day checkpoint, a newly registered village could receive a backlog accumulated before registration. Registration now records a stale day before setting the account cursor. Regression: `testFoundingCheckpointsStaleDayBeforeRegistering`.
2. **Empty-camp regrowth grief:** resetting a regrowth deadline on every attack could let raids on an already empty camp postpone defense indefinitely. Only the first damaging raid starts the deadline. Regression: `testRaidingEmptyCampCannotPostponeRegrowth`.
3. **Camp rate boundary:** charging an entire elapsed interval at the latest day's rate would retrospectively apply rate increases. Camp stock now integrates the daily rate across 04:00 UTC boundaries. `testCampDayChangesAtFourUTC` checks the boundary; `testCampProductionUsesBothRatesAcrossFourUTC` checks a split-rate interval against its independently calculated output.
4. **Malformed external return data:** high-level ABI decoding can produce unclear decode failures. The reader now checks exact lengths and every Core field's ABI width, then returns the named `ExternalReadFailed` error. Regression: `testMalformedAndMissingReadEndpointsHaveClearError`.

## Size adaptation and imported audit

The size adaptation preserves every constructor, immutable dependency, public function/event ABI, storage layout and authorization boundary. Its shared internal module-call helpers retain typed ABI encoding/decoding, STATICCALL for reads, code checks on void calls, strict minimum return lengths and exact revert propagation. They copy only a fixed expected reply size, never use delegate calls, and are compared against native Solidity calls in `ModuleCalls.t.sol`. The external Core/NFT reader implementations and gas allowances remain unchanged.

The imported audit's empty-support finding reproduced and is repaired: after all battle losses, empty contingents release their stationed slots and pair reservations and enter ordinary return. Existing casualty/upkeep accounting is unchanged. Canonical reinforcement, a full 30-slot list, mixed surviving/former support, nondecisive emptying and return events are covered; the war invariant rejects empty stationed support. [ADAPTATION.md](../ADAPTATION.md) records every imported observation, including the owner/read-dependency and resolution-time assumptions that intentionally remain.

## Review decisions and release responsibilities

[Economy](ECONOMY.md) records interpretations where the approved brief did not define an algorithm or boundary: missed-day attribution, checkpoint eligibility, starting champion points, plot counting, field cap, scout casualties, support score attribution, camp fractional composition, net Food settlement, decisive-only loot, medicine versus a wipe, weekly epoch, and delayed-resolution timing. In particular, a build deadline snapshots NFT holdings at the order, while future orders and current champion effects reflect transfers immediately.

The source tests do not establish that the supplied Sepolia addresses currently serve this ABI. The builder's live RPC/explorer attempts returned HTTP 403; the pinned interface uses the official documented eight-word Core layout and does not replace the supplied addresses with the different current docs address. The deployment service/reviewer must check both live reads and any proposed repoint.

This adaptation reproduces the supplied audit observations locally. No new Slither/Mythril run, independent audit, production fork test, explorer verification, or signed policy/artifact linkage was produced here. The required Foundry build, tests, invariant campaign, fuzz cases, formatting, ABI comparison, and runtime scan are recorded in [validation](VALIDATION.md). Independent adversarial review and deployment remain subsequent workflow responsibilities, not prerequisites supplied or impersonated by this source assignment.
