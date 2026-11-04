// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameTest} from "./helpers/GameTest.sol";
import {SeedLedger} from "../src/SeedLedger.sol";
import {MockCore, MockNFT, ReenteringCore, ShortCore, InvalidWidthCore, LongNFT} from "./helpers/Mocks.sol";

contract SeedLedgerTest is GameTest {
    function testInitialBalancesAndBaseline() public view {
        assertEq(game.seedBalance(alice), 1500 * U);
        assertEq(ledger.lastCumulativeWork(), 100_000);
        assertEq(ledger.lastWork(), 0);
        assertEq(ledger.observationCount(), 1);
    }

    function testDailyCheckpointAndClaimsExactlyOnce() public {
        _checkpoint(11_000);
        vm.prank(alice);
        (uint256 seed, uint256 xp) = game.claimSeed();
        assertEq(seed, 1100 * U);
        assertEq(xp, 110);
        assertEq(game.seedBalance(alice), 2600 * U);
        assertEq(game.seedBalance(bob), 1500 * U);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        vm.prank(alice);
        game.claimSeed();
        vm.expectRevert(SeedLedger.AlreadyCheckpointed.selector);
        ledger.checkpoint();
        vm.prank(bob);
        game.claimSeed();
        assertEq(game.seedBalance(bob), 2600 * U);
    }

    function testClaimsAggregateAndDoNotAwardHistoricalWorkToNewVillage() public {
        _checkpoint(11_000);
        _checkpoint(20_000);
        _found(carol, "Carol");
        vm.prank(alice);
        (uint256 seed, uint256 xp) = game.claimSeed();
        assertEq(seed, 3100 * U);
        assertEq(xp, 260);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        vm.prank(carol);
        game.claimSeed();
        _checkpoint(1000);
        vm.prank(carol);
        (seed, xp) = game.claimSeed();
        assertEq(seed, 100 * U);
        assertEq(xp, 10);
    }

    function testFoundingCheckpointsStaleDayBeforeRegistering() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        core.setWork(core.work() + 20000);
        _found(carol, "Carol");
        assertEq(ledger.lastWork(), 20000);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        vm.prank(carol);
        game.claimSeed();
        vm.prank(alice);
        game.claimSeed();
        assertEq(game.seedBalance(alice), 3500 * U);
    }

    function testFourUTCNotMidnightIsBoundary() public {
        uint256 day = ledger.currentDay();
        vm.warp((day + 1) * 1 days + 4 hours - 1);
        vm.expectRevert(SeedLedger.AlreadyCheckpointed.selector);
        ledger.checkpoint();
        vm.warp(vm.getBlockTimestamp() + 1);
        ledger.checkpoint();
        assertEq(ledger.currentDay(), day + 1);
    }

    function testDecreaseAndOracleFailureCannotAdvanceCursor() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        core.setWork(99_999);
        vm.expectRevert(SeedLedger.WorkDecreased.selector);
        ledger.checkpoint();
        assertEq(ledger.observationCount(), 1);
        core.setBroken(true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.checkpoint();
        assertEq(ledger.lastCumulativeWork(), 100_000);
    }

    function testRepointToSameCoreRebaselinesDecreasedCounter() public {
        core.setWork(99_000);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.expectRevert(SeedLedger.WorkDecreased.selector);
        ledger.checkpoint();
        vm.expectRevert(SeedLedger.WorkDecreased.selector);
        _found(carol, "Carol");
        assertEq(game.villageCount(), 2);
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.warp(vm.getBlockTimestamp() + 72 hours);
        vm.prank(owner);
        ledger.applyRepoint();
        assertEq(ledger.lastCumulativeWork(), 99_000);
        ledger.checkpoint();
        assertEq(ledger.lastWork(), 0);
        _found(carol, "Carol");
        assertTrue(game.village(carol).foundedAt != 0);
    }

    function testRepointToSameCoreKeepsUncheckpointedWork() public {
        core.setWork(105_000);
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.warp(vm.getBlockTimestamp() + 72 hours);
        vm.prank(owner);
        ledger.applyRepoint();
        assertEq(ledger.lastCumulativeWork(), 100_000);
        ledger.checkpoint();
        assertEq(ledger.lastWork(), 5000);
    }

    function testZeroWorkCheckpointStillClaimableOnce() public {
        _checkpoint(0);
        vm.prank(alice);
        (uint256 seed, uint256 xp) = game.claimSeed();
        assertEq(seed, 0);
        assertEq(xp, 0);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        vm.prank(alice);
        game.claimSeed();
    }

    function testUnauthorizedBurnRefundAndClaimCannotTouchCanonicalWorld() public {
        vm.expectRevert(SeedLedger.InsufficientSeed.selector);
        ledger.burn(alice, 1);
        vm.expectRevert();
        ledger.refund(alice, 1);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        ledger.claim(alice);
        ledger.register(alice);
        ledger.burn(alice, 1000 * U);
        ledger.refund(alice, 1000 * U);
        assertEq(game.seedBalance(alice), 1500 * U);
        assertEq(ledger.balanceOf(address(this), alice), 1500 * U);
    }

    function testRepointTimelockCancelReplaceRenounce() public {
        MockCore replacement = new MockCore();
        replacement.setWork(12);
        MockNFT replacementNFT = new MockNFT();
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.proposeRepoint(address(replacement), address(replacementNFT));
        vm.prank(owner);
        ledger.proposeRepoint(address(replacement), address(replacementNFT));
        vm.warp(vm.getBlockTimestamp() + 72 hours - 1);
        vm.expectRevert(SeedLedger.TimelockPending.selector);
        vm.prank(owner);
        ledger.applyRepoint();
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(owner);
        ledger.applyRepoint();
        assertEq(ledger.core(), address(replacement));
        assertEq(ledger.squeek(), address(replacementNFT));
        assertEq(ledger.lastCumulativeWork(), 12);
        ledger.checkpoint();
        assertEq(ledger.lastWork(), 0);
        replacement.setWork(1012);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        ledger.checkpoint();
        assertEq(ledger.lastWork(), 1000);
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.prank(owner);
        ledger.cancelRepoint();
        assertEq(ledger.repointAfter(), 0);
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.prank(owner);
        ledger.renounceOwnership();
        assertEq(ledger.owner(), address(0));
        assertEq(ledger.pendingCore(), address(0));
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        vm.prank(owner);
        ledger.applyRepoint();
    }

    function testReplacingProposalRestartsDelayAndFailedApplyPreservesProposal() public {
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.warp(vm.getBlockTimestamp() + 71 hours);
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.expectRevert(SeedLedger.TimelockPending.selector);
        vm.prank(owner);
        ledger.applyRepoint();
        vm.warp(vm.getBlockTimestamp() + 71 hours);
        nft.setBroken(true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        vm.prank(owner);
        ledger.applyRepoint();
        assertEq(ledger.pendingCore(), address(core));
        nft.setBroken(false);
        vm.prank(owner);
        ledger.applyRepoint();
    }

    function testNFTXPBonusUsesCurrentHolderAfterTransfer() public {
        nft.setBalance(alice, 1);
        _checkpoint(11000);
        nft.move(alice, bob);
        vm.prank(alice);
        game.claimSeed();
        vm.prank(bob);
        game.claimSeed();
        assertEq(army.champion(address(game), alice).xp, 110);
        assertEq(army.champion(address(game), bob).xp, 121);
    }

    function testFuzzMaximumWorkNeverOverflows(uint64 work) public {
        work = uint64(bound(work, 100_000, type(uint64).max));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        core.setWork(work);
        ledger.checkpoint();
        vm.prank(alice);
        game.claimSeed();
        assertEq(game.seedBalance(alice), 1500 * U + (uint256(work) - 100_000) * U / 10);
        assertLe(army.champion(address(game), alice).xp, 150);
        assertLe(ledger.wheelIntegral(10, vm.getBlockTimestamp() + 0), type(uint128).max);
    }

    function testWheelIntegralPreservesPastCheckpoints() public {
        _checkpoint(4320);
        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + 1 hours);
        assertEq(ledger.wheelIntegral(1, vm.getBlockTimestamp()), 3600 * U / 4);
        uint256 past = ledger.wheelIntegral(1, vm.getBlockTimestamp());
        _checkpoint(0);
        assertEq(ledger.wheelIntegral(1, t + 1 hours), past);
        uint256 nowIntegral = ledger.wheelIntegral(1, vm.getBlockTimestamp());
        vm.warp(vm.getBlockTimestamp() + 2 hours);
        assertEq(ledger.wheelIntegral(1, vm.getBlockTimestamp()), nowIntegral);
    }

    function testReentrantCoreCannotMutateStateDuringStaticRead() public {
        ReenteringCore bad = new ReenteringCore();
        SeedLedger probe = new SeedLedger(owner, address(bad), address(nft));
        bad.setTarget(address(probe));
        probe.checkpoint();
        assertEq(probe.observationCount(), 1);
    }

    function testMalformedAndMissingReadEndpointsHaveClearError() public {
        SeedLedger probe = new SeedLedger(owner, address(new ShortCore()), address(nft));
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        probe.checkpoint();
        probe = new SeedLedger(owner, address(new InvalidWidthCore()), address(nft));
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        probe.checkpoint();
        probe = new SeedLedger(owner, address(0x100333), address(nft));
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        probe.checkpoint();
        probe = new SeedLedger(owner, address(core), address(new LongNFT()));
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        probe.nftBalance(alice);
    }

    function testNFTFailureDuringClaimRollsBackSeedAndCursor() public {
        _checkpoint(11000);
        nft.setBroken(true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        vm.prank(alice);
        game.claimSeed();
        assertEq(game.seedBalance(alice), 1500 * U);
        assertEq(ledger.account(address(game), alice).cursor, 0);
        assertEq(ledger.minted(address(game)), 3000 * U);
        nft.setBroken(false);
        vm.prank(alice);
        game.claimSeed();
        assertEq(game.seedBalance(alice), 2600 * U);
    }
}
