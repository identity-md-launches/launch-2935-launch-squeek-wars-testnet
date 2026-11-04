# Squeek Wars — Testnet contracts

Solidity implementation of the approved Squeek Wars Testnet season on Sepolia (chain ID **11155111**). This repository supplies the contract-stage source, tests, ABI exports, deployment parameters, and review handoff. Publication, the independently generated `launch.json`, independent adversarial review, deployment, and the IPFS frontend are subsequent workflow contributions.

Players control one village per wallet. Resources and SEED are game accounting units, not tokens. There are no fees, payouts, deposits, token approvals, asset transfers, randomness, proxies, bots, upgrade paths, or administrative game controls. Normal ETH transfers revert.

## Build and verify

```sh
forge build
forge test
forge fmt --check
python3 tools/export_abi.py --check
```

`foundry.toml` pins Solidity **0.8.26**, Cancun, optimizer 200 runs, `via_ir = true`, and `bytecode_hash = "none"`. No FFI, filesystem permissions, remote imports, or external libraries are required. The full forge-std v1.9.7 source needed by the tests is vendored under `lib/forge-std/`, with its licenses. Production contracts have no third-party code dependencies.

The existing fuzz seed remains pinned to `0x212fae3293255b694ea7d1187d431edf2e8880f53f41a8696524766e24a60e26`. Fuzz tests run 256 cases; stateful invariants run 128 sequences of 64 actions. Tests use local mocks, explicit addresses, and virtual time; no environment variables, wallets, RPC, or real-time waits are needed. The adaptation also checks the assignment seed `0x06950b38af9f384b8df56e3fc33d7983649c01bf0e0bd48b5e8558383eade2b3`. Existing per-test fuzz and war-invariant settings are preserved. See [validation](docs/VALIDATION.md).

## Website (`web/` source, `dist/` static export)

The Squeek Wars Testnet site is a static Vite + React + TypeScript app. It reads Sepolia from the
browser through the public RPCs in `web/src/config.ts`, falling back between them, and caches
`eth_getLogs` chunks from block 12060202 in `localStorage`. The player's own wallet signs every
action. There is no server, indexer, key or analytics. Design tokens and components are described in [DESIGN.md](DESIGN.md).

```sh
cd web
npm ci              # install exactly what web/package-lock.json pins
npm run typecheck   # tsc --noEmit
npm run build       # tsc --noEmit && vite build -> ../dist (base "./", relative asset URLs)
npm run preview     # serve ../dist locally
npm run dev         # development server
```

`dist/` is committed and is what gets pinned to IPFS. Rebuild it after every source change. Routes
use the hash (`#/village`, `#/map`, ...), so the export works at a gateway subpath or an ENS name.

### Validation of the latest revision

This revision fixes eight review findings in `web/src`: loot amounts in battle reports from
`Army.report`, plain-English errors forwarded from Army/Clans/SeedLedger, current camp stock and
defense, Scout-only support, the boost-expiry rate, Ranking error states, name + short address in the
header/village/map, and the Rules champion/training text. Each one is answered in `.imd-responses.json`.

Limitation, stated plainly: the shell sandbox on the worker failed to start for the whole of this
revision ("Failed to create bridge sockets"). So `npm run typecheck`, `npm run build`, the interaction
tests and the design-critic probe (`taste.mjs`) were **not run**, and `dist/` is **still the export
from the previous accepted build**: it does not contain this revision's fixes. Each change was checked
only by reading it against the contract source (`src/Army.sol`, `src/Villages.sol`,
`src/SeedLedger.sol`) and `docs/ECONOMY.md`. Before publishing, run the commands above from `web/`
to regenerate `dist/`. No rendered check, screenshot or contrast measurement was made in this
revision. That includes the 320px fit of the new two-line wallet button.

## Contracts and deployment parameters

Deploy these five contracts, in this order, in the launch's single factory transaction. All constructors are nonpayable, use only static arguments, and make no external calls or code-existence checks.

| Contract | Constructor arguments in declaration order |
| --- | --- |
| `GameRules` | None |
| `SeedLedger` | `owner_ = $owner`, `core_ = 0x980b4424c007caf7a1f3670b48c8eaef7ebc3d44`, `squeek_ = 0xcb98349c134ab983da5bfd80527dfe2552bdb70f` |
| `Clans` | None |
| `Army` | `rules_ = $contract:GameRules`, `ledger_ = $contract:SeedLedger`, `clans_ = $contract:Clans` |
| `Villages` | `rules_ = $contract:GameRules`, `ledger_ = $contract:SeedLedger`, `clans_ = $contract:Clans`, `army_ = $contract:Army` |

`$owner` is resolved by the launch service to the paying wallet or the owner the request names; write it as `$owner`, not as a literal address. Only SeedLedger has an owner; it is always the explicit argument, never the deploying factory or transaction origin. The other four contracts are ownerless. Deployments must reference the same GameRules, SeedLedger, and Clans instances in both Army and Villages. There are no post-deployment module-wiring calls.

The existing `launch.json` preserves these parameters and was not rewritten by this adaptation. No transaction was broadcast. No launch token, distributor, or pool is needed. The size adaptation reaches **51,349 combined runtime bytes**, with a conservative local launch estimate of **89,836,861 gas**; [ADAPTATION.md](ADAPTATION.md) lists the changes and audit disposition.

## Architecture and authorization

- **GameRules:** pure economy tables, geometric growth, capacities, training costs, and build-time calculation.
- **SeedLedger:** 04:00 UTC checkpoints, nontransferable SEED, claim indexes, historical Wheelhouse integrals, live NFT reads, and the sole owner timelock.
- **Clans:** membership, capacity, and season/week ranking counters.
- **Army:** training, committed room, champion, asynchronous scouting/raids/support/returns, deterministic battles, reports, and camps.
- **Villages:** the **canonical player entry point**; names, map allocation, production, construction, research, Market, treasury, and authenticated calls into the other modules.

Every player command is sent to Villages and derives its actor from `msg.sender`. Player commands have no arbitrary source-village or recipient argument. Targets on movements do not convey authority over their owners.

The stateful helper modules key their data by `(calling game, player)`. Their canonical game is the deployed **Villages address**. This permits an acyclic constructor graph without an owner-controlled registration or initialization step. Calling `ledger.burn(alice, ...)`, `army.creditXP(alice, ...)`, or `clans.record(alice, ...)` directly only accesses the caller's separate namespace; it cannot affect the canonical village. Frontends must include the canonical Villages address in helper-module reads and event filters. Never merge data from other namespaces.

Villages' `army*` callbacks accept only its immutable Army. Army callbacks always use the namespace that created the movement. The only Army methods accepting an arbitrary game address execute already-created, due actions or return support that is no longer allied. External dependencies are called with `STATICCALL`; mutation routes that make external calls use reentrancy guards.

## Rules, units, and deliberate interpretations

The exact numeric tables are in GameRules. [Economy and state transitions](docs/ECONOMY.md) lists all formulas, rounding choices, and ambiguities resolved by this implementation. In particular:

- Resource order is **Wood, Food, Stone, Iron**. All resource and SEED amounts use **1,000,000 subunits per whole unit**. Troop counts, room, XP, and combat killed-value points are integers.
- The first checkpoint establishes the Core baseline without distributing historical work. Later checkpoints record one observed delta per game day. Founding checkpoints a stale day before registering the new account. Claims receive only observations after registration.
- Missing checkpoint days cannot be reconstructed from `state()`. Their cumulative delta belongs to the next observed day; SEED is not multiplied by the number of missed days, and no daily history is fabricated. The latest recorded work remains the output/build-work signal until replaced.
- Buildings and research take effect when completed permissionlessly, never retroactively. Two construction slots and one sequential research slot exist. Cancel before readiness for 80% of paid resource and SEED costs; canceled builds give no ranking points.
- Build-time NFT counts are sampled **at order creation**, as the brief specifies. That order's deadline is final. New orders, champion stats at battle, and XP when awarded always re-read current NFT ownership. NFT reduction is at most 30%; the separate Town Hall reduction also applies.
- Resource production and troop upkeep settle lazily. Food cannot go below zero; unpaid upkeep does not create debt or kill troops. All committed room, including queued, deployed, and supporting units, consumes upkeep.
- Combat has no random input. A decisive attack (`attack >= 2 * defense`, with positive attack) wipes the garrison and permits loot/siege; other outcomes only cause casualties. Casualties round up once per army (largest-remainder apportionment across troop types), not per type. Field Medicine returns floor(10% of losses), except a decisive defender wipe.
- Raids are limited to three **per attacker and target per game day**, separately at departure and arrival. Support and scouting are not raids. Offensive dispatch drops the sender's shield. Shields and clan membership are rechecked at arrival; protected targets cause a safe return without combat. Clan membership needs the founder's invitation (`Villages.inviteToClan`), so nobody can make themselves an attacker's clanmate.
- The map is a fixed affine permutation, `tile = (7919 * slot + 1237) % 10000`. Slots 49, 99, …, 9999 are camps; 9,800 village positions remain. This is deterministic placement, not valuable randomness.
- One immutable Testnet season spans this deployment. Weekly counters use successive seven-day windows from deployment. No owner can reset the season, alter balances, pause, change rules, or change another player's actions.

## After launch

1. **Deployment service:** publish and attest source, admit the independently reviewed manifest, deploy, verify source on the explorer, and provide the confirmed five-contract set to the frontend. No deployment addresses are invented here.
2. **Endpoint check:** read the approved Core's `state()` and the approved NFT's `balanceOf(address)` on Sepolia. The pinned [interface](src/interfaces/ISqueek.sol) uses eight Core return words, with `uint64 cumulativeWork` second. Its layout is documented by the [Squeekchain Core reference](https://docs.squeekchain.com/developers/core/). Public documentation currently lists another deployment address; this implementation preserves the brief's addresses. Live endpoint compatibility was not established in this assignment (RPC/explorer access returned HTTP 403). Local mocks validate decoding and failure paths, not deployment compatibility.
3. **Players / anyone:** call `SeedLedger.checkpoint()` once per 04:00 UTC day. The first village also creates the initial baseline if needed. No bot or keeper is required or privileged. Players claim with `Villages.claimSeed()`.
4. **Players / anyone:** finalize ready builds/research/training and resolve arrived movements. Delayed resolution has the documented timing semantics; the protocol does not autonomously submit transactions. The frontend should expose checkpoint, claim, completion, and resolve buttons.
5. **Owner, only if an external read endpoint must change:** propose the verified replacement Core/NFT pair with `SeedLedger.proposeRepoint(core, squeek)`, wait **72 hours**, then call `applyRepoint()`. Get replacement addresses from the official Squeek deployment records for Sepolia and independently verify the same ABI. Both arguments must be nonzero; keep the unchanged address when changing only one. A new Core is baselined at application and gives no historical windfall. If the approved Core's counter ever reads below the recorded baseline (checkpoints and founding revert `WorkDecreased`), propose the **same** Core/NFT pair: applying it rebaselines to the live value and restores checkpoints. `cancelRepoint()` cancels; a replacement proposal restarts the whole delay. `renounceOwnership()` permanently cancels pending work and removes this power. There is no other owner setting.
6. **Independent reviewer:** assess accepted source, tests, and the actual manifest together, especially dependency consistency, timelock authority, namespaces, and the documented economic interpretations. [Security handoff](docs/SECURITY.md) is a builder's review, not an independent audit or admission attestation.

No wallet key, signer, fee rate, payable funding, randomness subscription, or external service account is required to operate this game.
