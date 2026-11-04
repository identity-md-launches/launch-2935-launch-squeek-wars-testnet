# Additional adversarial tests

This contribution adds tests to the accepted size adaptation. It changes no application source,
existing test, manifest, dependency, or build configuration. The protected constructor/owner checks
and the supplied Pashov fizz and Trail of Bits property-testing references informed the review.
All five discovery passes were performed locally; no subagents were used.

## Property selection

| Discovery pass | Property and basis | Added coverage |
| --- | --- | --- |
| Conservation | Each namespace's balances plus net burned SEED equal gross issuance. Each account receives only observations after registration, exactly once. `SeedLedger.sol:178`, `:190`, `:202`, `:211`; Economy, “Time, checkpoints, and SEED”. | `LedgerModelInvariants.t.sol`: a separate per-account entitlement model across two game namespaces and three players, including late registration, zero-work observations, full-balance burns/refunds, and claims before/after repoints. |
| State transitions | A failed operation leaves its state retryable; only a successful due repoint can change readers. `SeedLedger.sol:133`, `:237`; Security, “External calls and liveness”. | The invariant handler interleaves proposal/replacement/cancellation, early application, unauthorized calls, failed checkpoints and recovery. Reader tests check rollback of a tentative baseline when the replacement NFT is invalid. |
| Round trips and rounding | Repeated construction order/cancel loses the rounded-up 20% fee, preserves levels, clears the slot and earns no ranking points. Daily and batched claims agree for players without NFT bonuses. `Villages.sol:284`, `:377`; Economy, “Fields and buildings”. | `GameplayAtomicity.t.sol` fuzzes 16 targets, both slots and up to five cycles. `CheckpointProperties.t.sol` compares two claim schedules without duplicating the cumulative-index implementation. |
| Adversarial inputs | External data must have exact lengths and valid widths, remain static, and fit the read gas allowance. A rejected late dispatch cannot consume troops or the raid quota. `SeedLedger.sol` readers; `Army.sol:289`; Security, “External calls and liveness”. | `ReaderValidation.t.sol` covers every constrained Core word, short/long replies, reverting/writing/exhausting readers and retry. Dispatch tests fail after earlier troop debits and after the daily counter increment, then demonstrate all three valid departures remain available. |
| Protocol-specific properties | This game has nontransferable accounting, asynchronous orders and a reader timelock, rather than token custody or a pool. Checkpoint history is immutable and output cannot exceed the Wheelhouse level cap. `SeedLedger.sol:163`; Economy, “Storage, output, upkeep, and treasury”. | Historical queries at exact and intermediate timestamps remain unchanged after later observations for every Wheelhouse level. Explicit maximum-work and zero-work tests check saturation and cessation of growth. Existing game and war invariants remain intact. |

These are documented guarantees, not speculative requirements such as immutable live NFT rewards,
arrival-time snapshots, or owner-independent work readers. The tests preserve the implementation's
documented semantics for those cases.

## Harness scope

The ledger model computes pending rewards for individual accounts as observations arrive. It does
not read the ledger's seed/XP indices to derive expected balances. Ghost values change only after
successful calls. Handler actions constrain valid amounts and explicitly exercise zero, one
subunit, the full available amount and amounts above the permitted balance. Expected failures check
specific error selectors; unexpected reverts fail the campaign. A deterministic driver reaches
registration, claim, full burn/refund and both same-stream and different-stream repoints.

The model's two test game callers exercise the public namespace API. The module's refund budget is
per namespace; the canonical player's additional construction-cost limit is checked through
Villages in the round-trip tests. No test claims that a direct helper namespace is a player API.
Gameplay fixtures use ordinary founding, building, checkpointing and training calls. Reader mocks
can deliberately return malformed bytes; none is a production dependency or manifest address.

The added campaign uses 256 sequences of 96 calls (24,576 handler calls), with two invariant
properties checked after each call. Six additional parameterized fuzz tests run 5,512 inputs per
full suite: five at 1,000 inputs and one at 512. There are also thirteen new deterministic tests.
The existing tests and their run counts are unchanged.

## Reproduction

The tests run offline with the repository's existing vendored dependencies. Compiler output and
logs were kept in disposable `test/scratch/`; no submitted test imports anything there. Standard
`forge build` and `forge test` use the same source and compiler settings. The artifact-location
flags below merely keep this assignment's generated files inside its permitted paths.

```sh
forge build --sizes --out test/scratch/out --cache-path test/scratch/cache
forge test --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x06950b38af9f384b8df56e3fc33d7983649c01bf0e0bd48b5e8558383eade2b3 \
  forge test --out test/scratch/out --cache-path test/scratch/cache
forge test --out test/scratch/out --cache-path test/scratch/cache \
  --match-path test/LaunchBudget.t.sol -vv
```

These local checks do not establish current Sepolia endpoint compatibility or replace the
deployment service's actual transaction preflight. The original launch rehearsal remains the
one-call, five-constructor graph with the brief's endpoints and an explicit test paying wallet.

## Checked results (2026-11-04)

These figures were measured before the `_refreshCamp` repair (`ADAPTATION.md`, finding `b93138d9…`) and
have not been re-measured here. That repair is why they differ from `docs/VALIDATION.md`, which records
Army 19,180, combined 51,349 and an estimate of 89,836,861 gas, and is the record to use for the launch.
By reading the code only: none of the tests added here resolves a camp raid, so the repair should not
touch them, but no `forge` run on the repaired source backs that.

`forge build --sizes` passed. Both the repository-default test run and the explicit assignment-seed
run passed **153 reported checks across 25 suites, with zero failures and zero skips**. This adds
20 reported checks to the accepted implementation's 133. Forge groups the two new invariant
properties into one reported check; each campaign executed 24,576 handler calls with zero unexpected
reverts. Formatting and the path-scope check passed. No new violation of the documented contract
behavior was reproduced by these tests.

The five application runtime sizes are unchanged:

| Contract | Runtime bytes |
| --- | ---: |
| Army | 19,199 |
| Villages | 17,090 |
| SeedLedger | 5,770 |
| GameRules | 4,225 |
| Clans | 5,084 |
| **Combined** | **51,368** |

The existing launch rehearsal passed with **11,444,055** local execution gas and **53,316** calldata
bytes. Its estimate remains **89,870,111 gas**: local execution plus `51,368 * 1,500` for the
additional code-deposit charge, 21,000 intrinsic gas, `53,316 * 16` calldata gas and a 500,000-gas
factory allowance. These figures agree with the accepted `docs/VALIDATION.md`, which is outside this
test-only assignment's writable paths and was left unchanged.
