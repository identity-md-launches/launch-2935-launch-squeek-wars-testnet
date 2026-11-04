# Validation

The project builds with pinned Solidity 0.8.26 and the checked-in Foundry settings. No network, environment variables, broadcast keys, or uncommitted dependencies are required by tests. forge-std v1.9.7 is vendored as ordinary files, with its upstream MIT and Apache licenses.

Commands checked for this adaptation (2026-11-04):

```sh
forge build
forge test
FOUNDRY_FUZZ_SEED=0x06950b38af9f384b8df56e3fc33d7983649c01bf0e0bd48b5e8558383eade2b3 forge test
forge build --sizes
forge test --match-path test/LaunchBudget.t.sol -vv
forge fmt --check
python3 tools/export_abi.py --check
```

Additional checks include focused regression runs, comparison with the original public ABIs, and the deployed-bytecode opcode scan in `Deployment.t.sol`. The protected configuration remains unchanged, including its seed `0x212fae3293255b694ea7d1187d431edf2e8880f53f41a8696524766e24a60e26`. The second full run explicitly uses the assignment seed shown above.

Each full run exercises twelve parameterized fuzz tests: eight at 256 inputs, two existing edge-case tests at 512, and two at 1,000 (5,072 inputs total). The five game invariants run together for 128 sequences at depth 64 (8,192 handler calls). The five war invariants retain their original per-test settings of 48 sequences at depth 60 (2,880 calls). No fuzz depth, run count, seed configuration, test or assertion was removed to meet the size target.

| Test source | Coverage |
| --- | --- |
| `SeedLedger.t.sol` | Initial baseline, daily boundary/replay, zero work, batch claims, new-village eligibility, counter decreases and same-Core repoint recovery, uint64 maximum work, namespace isolation, live NFT XP, historical output integral, missing/malformed/reentrant readers, timelock cancellation/replacement/renunciation |
| `Rules.t.sol` | Numeric quote checks, all maximum levels/units, invalid inputs, exhaustive 10,000-tile permutation, camp separation, distance, capacity monotonicity fuzz, 30% NFT reduction bound fuzz |
| `Villages.t.sol` | Founding/name rules, map allocation, two build slots, plot reservations, cancel refunds, queue replay, research prerequisites/counters, production and fractional-settlement fuzz, storage, Market burn/cap rollback, treasury duration/cooldown and no-charge refusal under a longer shield, NFT order snapshots, reader failure rollback, callback access control, ETH rejection |
| `Army.t.sol` | Training reservations/upkeep, unlock/room limits, return replay, troop/champion locking, shield changes in flight, raid limits, current NFT stats, point caps, recoverable settlement failure, loot/Vault conservation, low-TH treatment, scouts, camp regrowth/caps, Catapult damage/repair, maximum canonical army |
| `CombatMath.t.sol` | Independent integer casualty reference fuzz to one million troops per side, mixed-army whole-army rounding fuzz and the lone-stack regression, zero-attack handling, callback reentrancy, NFT transfer during travel, empty-camp deadline regression, scouts-only raid cannot freeze camp defense, 04:00 UTC camp day |
| `Clans.t.sol` | Found/invite/join/leave prerequisites, uninvited join refused and cannot cancel a raid, founder-only and revocable invitations, capacity, founder controls, no friendly raids, troop-only support/recall, former-clan return, join during incoming attack, support losses/origin room, season/week score formula and namespace isolation |
| `Deployment.t.sol` | Constructors with absent dependency code, explicit ownership, zero-argument rejection, all runtime sizes and reachable forbidden-opcode scan |
| `Invariants.t.sol` | Stateful public-API actions with checkpoint/time changes, claims, builds/cancellations, research, Market, treasury, training, camps, returns, and settlement |
| `EdgeCases.t.sol` | Original registration/refund/owner, prerequisite, name, exchange, shield, movement, training and champion rejection coverage; existing 512/1,000-case fuzz settings |
| `WarInvariants.t.sol` | Resource/SEED conservation across raids and returns, raid limits, clan churn, room/champion/support accounting and bounds; now also rejects empty stationed support |
| `RulesEncoding.t.sol`, `helpers/ReferenceRules.sol` | Byte-for-byte return comparison against the original economy tables/formulas over all legal fields, buildings, units, Barracks levels and unlock tiers, three troop counts, capacities and research tiers, plus build-duration fuzz |
| `ModuleCalls.t.sol` | Shared internal calls versus native Solidity calls: return values, short/malformed/trailing replies, absent code, static restrictions, revert-byte fuzz and state rollback |
| `SupportCleanup.t.sol`, extended `Clans.t.sol` | Reproduced empty-support bug, immediate reinforcement, full 30-slot list, former and surviving support, nondecisive emptying, return events and empty return completion |
| `AuditAssumptions.t.sol`, extended `SeedLedger.t.sol` | Owner-selected future work rewards; founding rollback and same-Core recovery; shield-at-resolution semantics |
| `LaunchBudget.t.sol` | Five CREATE2 deployments in one call, original constructor graph/endpoints, paying-wallet ownership, combined runtime cap and conservative gas estimate |

The stateful properties checked after randomized actions are:

1. Canonical SEED balances sum to minted minus net burned; non-loot actions cannot change another village's current resources or SEED.
2. Every resource stays at or below its village's storage limit.
3. Committed room equals the sum of home troops, training queue, and all live movements/support, and never exceeds capacity.
4. Each wallet retains exactly its own village and distinct tile.
5. Checkpoint days strictly increase, and the applications accept no normal ETH custody.

Ordinary integration tests and the invariant setup use player actions. Late-game fixtures explicitly impersonate the immutable Army callback only to supply resources for expensive endgame setup; the fixture is test-only, and separate tests reject all unprivileged calls to that callback. `ArmyWorld` is an isolated test namespace with generous room/resources for independent arithmetic fuzzing; it is never a launch application and cannot affect the canonical game.

These checks are implementation evidence, not a formal proof or an independent security audit. All test/helpers remain in `test/` and are delivered; no submitted source depends on `test/scratch/`.

## Recorded final result

The incoming code passed **118 reported checks** before adaptation. Adding the empty-support regression to that source reproduced the audit finding: `testSupportDefendsAndLossesReleaseOriginsRoom` failed with `5 != 4` because the empty movement remained stationed. No original test was removed.

The final `forge test` run passed **134 reported checks across 20 suites, zero failures and zero skipped**, including all ten invariant properties. The explicit assignment-seed run also passed **134 checks, zero failures and zero skipped**. Both campaigns retained the run/depth settings above. `forge build`, `forge build --sizes`, `forge fmt --check`, and `python3 tools/export_abi.py --check` exited successfully. The build still reports advisory Forge lint warnings; no lint suppressions or build settings were added.

The five application ABI exports were regenerated from the final build. Comparing them with the incoming exports after excluding only `error` entries found **identical constructors, functions and events**, including mutability and tuple fields. All module bindings remain Solidity `immutable`; storage declarations/layouts remain unchanged. `launch.json` and `foundry.toml` compare byte-for-byte with their incoming copies. No dependencies or protected paths were edited.

### Sizes from `forge build --sizes`

Only the five applications named in the existing manifest are summed. Libraries are internal and test fixtures are not launch applications.

| Contract | Original runtime bytes | Final runtime bytes | Final initcode bytes (before arguments) | Constructor argument bytes |
| --- | ---: | ---: | ---: | ---: |
| GameRules | 5,717 | 4,225 | 4,251 | 0 |
| SeedLedger | 6,078 | 5,770 | 6,064 | 96 |
| Clans | 5,660 | 5,084 | 5,130 | 0 |
| Army | 23,644 | 19,180 | 19,513 | 96 |
| Villages | 20,583 | 17,090 | 17,562 | 128 |
| **Combined** | **61,682** | **51,349** | **52,520** | **320** |

Runtime decreased by **10,333 bytes (16.75%)**, leaving **651 bytes** under the combined 52,000-byte cap. Each application is below EIP-170's 24,576-byte runtime limit and EIP-3860's 49,152-byte initcode limit including arguments. The cap on initcode applies per contract, not to their sum. No application has an external-library link reference. The original deployment test scans every instantiated runtime for the protected floor's forbidden reachable opcodes; the constructor tests still deploy successfully with absent dependency code.

### Estimated launch gas

`LaunchBudgetTest.testFactoryGraphOwnerAndConservativeLaunchGas` deploys the unchanged graph through one local CREATE2 factory call on chain ID 11155111, using the supplied Core/NFT addresses and an explicit test paying wallet. The production manifest continues to use `$owner`. The rehearsal requires no deployed external endpoint, environment variable or initialization call.

The project targets Cancun, which locally accounts for 200 gas per deposited runtime byte. To model the brief's approximately **1,700 gas per byte**, the test adds another 1,500 per runtime byte. It then adds transaction intrinsic gas, a conservative all-nonzero calldata charge and a separate 500,000-gas allowance for the production factory's unmodeled work:

| Component | Gas |
| --- | ---: |
| Measured local CREATE2 execution, including all five constructors and ordinary code deposit | 11,439,817 |
| Additional code-deposit charge: `51,349 × (1,700 − 200)` | 77,023,500 |
| Transaction intrinsic gas | 21,000 |
| All-nonzero calldata upper bound: `53,284 bytes × 16` | 852,544 |
| Additional factory allowance | 500,000 |
| **Estimated total** | **89,836,861** |

This is **163,139 gas below 90,000,000**, including the allowance, and **10,065,483 gas below the brief's quoted 99,902,344 cap**. The test asserts both the runtime and gas budgets so a source change cannot silently exceed them.

This is a reproducible local estimate under the brief's gas-price assumption, not a broadcast or a fresh Sepolia simulation. The deployment service must apply its actual factory overhead, then-current chain gas schedule/cap and final admission preflight. The exact current live endpoints and their upstream upgradeability were not reverified here; the input audit's live observations and their local reproductions are distinguished in [ADAPTATION.md](../ADAPTATION.md).
