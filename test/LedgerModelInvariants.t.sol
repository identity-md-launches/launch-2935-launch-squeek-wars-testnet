// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SeedLedger} from "src/SeedLedger.sol";
import {GameErrors as E} from "src/libraries/GameErrors.sol";
import {MockCore, MockNFT} from "./helpers/Mocks.sol";

/// @dev A per-account entitlement model, independent of the ledger's cumulative-index algorithm.
/// The two caller namespaces are test games, not impersonations of the production Villages.
contract LedgerModelHandler is Test {
    uint256 private constant U = 1_000_000;
    SeedLedger public immutable ledger;
    address private immutable owner;
    MockCore[2] private sources;
    MockNFT private immutable nft;
    address[2] public games;
    address[3] public players;

    struct Entitlement {
        bool registered;
        uint256 balance;
        uint256 pendingSeed;
        uint256 pendingXP;
        uint256 cursor;
    }

    Entitlement[3][2] private expected;
    uint256[2] private issued;
    uint256[2] private destroyed;
    uint256 public observations;
    uint256 private observedDay;
    uint64 private baseline;
    uint8 private activeSource;
    uint8 private proposedSource;
    uint256 private executableAt;
    uint256 public successfulClaims;
    uint256 public successfulBurns;
    uint256 public successfulRefunds;
    uint256 public successfulRepoints;

    constructor(SeedLedger ledger_, MockCore a, MockCore b, MockNFT nft_, address owner_) {
        ledger = ledger_;
        sources = [a, b];
        nft = nft_;
        owner = owner_;
        games = [makeAddr("ledger-model-game-0"), makeAddr("ledger-model-game-1")];
        players =
            [makeAddr("ledger-model-alice"), makeAddr("ledger-model-bob"), makeAddr("ledger-model-carol")];
    }

    function _day() private view returns (uint256) {
        return (vm.getBlockTimestamp() - 4 hours) / 1 days;
    }

    // Update only after a successful checkpoint, including one implicitly made by register.
    // Pending rewards are credited to each eligible account rather than copied from ledger indices.
    function _observe() private {
        uint64 current = sources[activeSource].work();
        uint256 work = observations == 0 ? 0 : uint256(current) - baseline;
        uint256 seed = work * 100_000;
        uint256 xp = work / 100;
        if (xp > 150) xp = 150;
        for (uint256 g; g < 2; ++g) {
            for (uint256 p; p < 3; ++p) {
                Entitlement storage e = expected[g][p];
                if (e.registered) {
                    e.pendingSeed += seed;
                    e.pendingXP += xp;
                }
            }
        }
        baseline = current;
        observedDay = _day();
        ++observations;
    }

    function advance(uint32 seconds_, uint64 work) external {
        vm.warp(vm.getBlockTimestamp() + bound(seconds_, 0, 4 days));
        MockCore source = sources[activeSource];
        uint64 current = source.work();
        source.setWork(current + uint64(bound(work, 0, type(uint64).max - current)));
    }

    function checkpoint() public {
        if (observations != 0 && observedDay == _day()) {
            vm.expectRevert(SeedLedger.AlreadyCheckpointed.selector);
            ledger.checkpoint();
            return;
        }
        ledger.checkpoint();
        _observe();
    }

    function register(uint8 game_, uint8 player_) public {
        uint256 g = game_ % 2;
        uint256 p = player_ % 3;
        Entitlement storage e = expected[g][p];
        if (e.registered) {
            vm.expectRevert(E.AlreadyRegisteredOrInvalidPlayer.selector);
            vm.prank(games[g]);
            ledger.register(players[p]);
            return;
        }
        vm.prank(games[g]);
        ledger.register(players[p]);
        if (observations == 0 || observedDay < _day()) _observe();
        e.registered = true;
        e.balance = 1500 * U;
        e.cursor = observations - 1;
        issued[g] += 1500 * U;
    }

    function claim(uint8 game_, uint8 player_) public {
        uint256 g = game_ % 2;
        uint256 p = player_ % 3;
        Entitlement storage e = expected[g][p];
        if (!e.registered || e.cursor + 1 == observations) {
            vm.expectRevert(SeedLedger.NoClaim.selector);
            vm.prank(games[g]);
            ledger.claim(players[p]);
            return;
        }
        vm.prank(games[g]);
        (uint256 seed, uint256 xp) = ledger.claim(players[p]);
        assertEq(seed, e.pendingSeed, "claim must equal this account's unclaimed observations");
        assertEq(xp, e.pendingXP, "XP entitlement must survive batching and repoints");
        e.balance += e.pendingSeed;
        issued[g] += e.pendingSeed;
        e.pendingSeed = 0;
        e.pendingXP = 0;
        e.cursor = observations - 1;
        ++successfulClaims;
    }

    function _amount(uint256 raw, uint8 edge, uint256 available) private pure returns (uint256) {
        if (edge % 4 == 0) return 0;
        if (edge % 4 == 1) return available == 0 ? 0 : 1;
        if (edge % 4 == 2) return available;
        return bound(raw, 0, available);
    }

    function burn(uint8 game_, uint8 player_, uint256 raw, uint8 edge) public {
        uint256 g = game_ % 2;
        uint256 p = player_ % 3;
        Entitlement storage e = expected[g][p];
        if (!e.registered) {
            vm.expectRevert(SeedLedger.InsufficientSeed.selector);
            vm.prank(games[g]);
            ledger.burn(players[p], 0);
            return;
        }
        uint256 amount = _amount(raw, edge, e.balance);
        vm.prank(games[g]);
        ledger.burn(players[p], amount);
        e.balance -= amount;
        destroyed[g] += amount;
        ++successfulBurns;
    }

    function refund(uint8 game_, uint8 player_, uint256 raw, uint8 edge) public {
        uint256 g = game_ % 2;
        uint256 p = player_ % 3;
        Entitlement storage e = expected[g][p];
        if (!e.registered) {
            vm.expectRevert(E.InvalidRefund.selector);
            vm.prank(games[g]);
            ledger.refund(players[p], 0);
            return;
        }
        // The module's refund ceiling is per game. Canonical Villages additionally limits
        // refunds to its player's recorded construction cost; that restriction is tested there.
        uint256 amount = _amount(raw, edge, destroyed[g]);
        vm.prank(games[g]);
        ledger.refund(players[p], amount);
        e.balance += amount;
        destroyed[g] -= amount;
        ++successfulRefunds;
    }

    function rejectOverdraw(uint8 game_, uint8 player_) external {
        uint256 g = game_ % 2;
        uint256 p = player_ % 3;
        uint256 tooMuch = expected[g][p].balance + 1;
        vm.expectRevert(SeedLedger.InsufficientSeed.selector);
        vm.prank(games[g]);
        ledger.burn(players[p], tooMuch);
        tooMuch = destroyed[g] + 1;
        vm.expectRevert(E.InvalidRefund.selector);
        vm.prank(games[g]);
        ledger.refund(players[p], tooMuch);
    }

    function failedCheckpointThenRecover() external {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        MockCore source = sources[activeSource];
        source.setBroken(true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.checkpoint();
        assertEq(ledger.observationCount(), observations, "failed read appended an observation");
        assertEq(ledger.lastCumulativeWork(), baseline, "failed read changed baseline");
        source.setBroken(false);
        checkpoint();
    }

    function propose(uint8 source) public {
        proposedSource = source % 2;
        vm.prank(owner);
        ledger.proposeRepoint(address(sources[proposedSource]), address(nft));
        executableAt = vm.getBlockTimestamp() + 72 hours;
    }

    function executeRepoint() public {
        if (executableAt == 0 || vm.getBlockTimestamp() < executableAt) {
            vm.expectRevert(SeedLedger.TimelockPending.selector);
            vm.prank(owner);
            ledger.applyRepoint();
            return;
        }
        vm.prank(owner);
        ledger.applyRepoint();
        if (activeSource != proposedSource) baseline = sources[proposedSource].work();
        activeSource = proposedSource;
        executableAt = 0;
        ++successfulRepoints;
    }

    function cancel() external {
        vm.prank(owner);
        ledger.cancelRepoint();
        executableAt = 0;
    }

    function rejectForeignOwner(uint8 game_) external {
        address caller = games[game_ % 2];
        vm.startPrank(caller);
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.proposeRepoint(address(sources[1]), address(nft));
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.applyRepoint();
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.cancelRepoint();
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.renounceOwnership();
        vm.stopPrank();
    }

    function assertAccountsAndConservation() external view {
        for (uint256 g; g < 2; ++g) {
            uint256 sum;
            for (uint256 p; p < 3; ++p) {
                Entitlement memory e = expected[g][p];
                SeedLedger.Account memory a = ledger.account(games[g], players[p]);
                assertEq(a.exists, e.registered, "registration leaked across namespaces");
                assertEq(a.balance, e.balance, "account differs from independent cash-flow model");
                assertEq(a.cursor, e.cursor, "claim cursor changed without a successful claim");
                sum += a.balance;
            }
            assertEq(ledger.minted(games[g]), issued[g], "gross mint accounting");
            assertEq(ledger.burned(games[g]), destroyed[g], "net burn accounting");
            assertEq(sum + destroyed[g], issued[g], "SEED conservation per namespace");
        }
    }

    function assertCheckpointAndAuthorityState() external view {
        assertEq(ledger.observationCount(), observations);
        assertEq(ledger.lastCumulativeWork(), baseline);
        assertEq(ledger.core(), address(sources[activeSource]));
        assertEq(ledger.squeek(), address(nft));
        assertEq(ledger.owner(), owner);
        assertEq(ledger.repointAfter(), executableAt);
        assertEq(ledger.pendingCore(), executableAt == 0 ? address(0) : address(sources[proposedSource]));
        assertEq(ledger.pendingSqueek(), executableAt == 0 ? address(0) : address(nft));
        if (observations != 0) assertEq(ledger.observation(observations - 1).day, observedDay);
        for (uint256 i = 1; i < observations; ++i) {
            SeedLedger.Observation memory a = ledger.observation(i - 1);
            SeedLedger.Observation memory b = ledger.observation(i);
            assertGt(b.day, a.day);
            assertGt(b.timestamp, a.timestamp);
            assertGe(b.seedIndex, a.seedIndex);
            assertGe(b.xpIndex, a.xpIndex);
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract LedgerModelInvariantTest is StdInvariant, Test {
    LedgerModelHandler private handler;

    function setUp() public {
        vm.warp(1_800_000_000);
        MockCore a = new MockCore();
        MockCore b = new MockCore();
        b.setWork(7);
        MockNFT nft = new MockNFT();
        SeedLedger ledger = new SeedLedger(address(this), address(a), address(nft));
        handler = new LedgerModelHandler(ledger, a, b, nft, address(this));
        handler.register(0, 0);
        handler.register(0, 1);
        handler.register(1, 0);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = handler.advance.selector;
        selectors[1] = handler.checkpoint.selector;
        selectors[2] = handler.register.selector;
        selectors[3] = handler.claim.selector;
        selectors[4] = handler.burn.selector;
        selectors[5] = handler.refund.selector;
        selectors[6] = handler.rejectOverdraw.selector;
        selectors[7] = handler.failedCheckpointThenRecover.selector;
        selectors[8] = handler.propose.selector;
        selectors[9] = handler.executeRepoint.selector;
        selectors[10] = handler.cancel.selector;
        selectors[11] = handler.rejectForeignOwner.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariant_balancesMatchEntitlementsAndConserveSeedInEachNamespace() public view {
        handler.assertAccountsAndConservation();
    }

    function invariant_checkpointHistoryAndTimelockMatchAuthorizedActions() public view {
        handler.assertCheckpointAndAuthorityState();
    }

    function testModelExercisesLateRegistrationFullBurnRefundAndBothRepointPaths() public {
        handler.advance(2 days, 11000);
        handler.register(1, 2); // Registration checkpoints before this player becomes eligible.
        handler.claim(1, 2); // No historical claim.
        handler.claim(0, 0);
        handler.burn(0, 0, 0, 2);
        handler.refund(0, 0, 0, 2);
        handler.rejectOverdraw(0, 0);
        handler.propose(1);
        handler.executeRepoint(); // Too early, with the proposal intact.
        handler.advance(3 days, 0);
        handler.executeRepoint(); // Different stream: discard its old history.
        handler.checkpoint();
        handler.claim(0, 1); // Rewards recorded before the repoint survive.
        handler.propose(1);
        handler.advance(3 days, 99);
        handler.executeRepoint(); // Same stream: uncheckpointed work survives.
        handler.checkpoint();
        handler.claim(1, 2);
        handler.claim(1, 2); // Replay rejected.
        handler.assertAccountsAndConservation();
        handler.assertCheckpointAndAuthorityState();
        assertEq(handler.successfulClaims(), 3);
        assertEq(handler.successfulBurns(), 1);
        assertEq(handler.successfulRefunds(), 1);
        assertEq(handler.successfulRepoints(), 2);
    }
}
