// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {EndgameTest} from "./helpers/EndgameTest.sol";
import {MockCore} from "./helpers/Mocks.sol";
import {Army} from "../src/Army.sol";

/// @notice Reproduces the imported informational observations without changing these agreed rules.
contract AuditAssumptionsTest is EndgameTest {
    function testOwnerSelectedCoreControlsFutureWorkRewardsAfterDelay() public {
        MockCore replacement = new MockCore();
        replacement.setWork(0);
        vm.prank(owner);
        ledger.proposeRepoint(address(replacement), address(nft));
        vm.warp(vm.getBlockTimestamp() + 72 hours);
        vm.prank(owner);
        ledger.applyRepoint();
        assertEq(ledger.lastCumulativeWork(), 0);
        assertEq(game.seedBalance(alice), 1500 * U);
        replacement.setWork(1_000_000_000);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        ledger.checkpoint();
        vm.prank(alice);
        (uint256 seed, uint256 xp) = game.claimSeed();
        assertEq(seed, 100_000_000 * U);
        assertEq(xp, 150);
        assertEq(army.champion(address(game), alice).xp, 150);
    }

    function _raidWithShieldAtNominalArrival() private returns (uint256 id, uint256 arrival) {
        _barracks(alice);
        _troops(alice, 0, 30);
        vm.warp(game.village(bob).shieldUntil);
        _checkpoint(100_000);
        vm.prank(bob);
        game.claimSeed();
        id = _send(alice, bob, 0, 0, 30, false, 1);
        arrival = army.movement(address(game), id).arriveAt;
        vm.warp(arrival - 1 hours);
        vm.prank(bob);
        game.treasury(1, 0);
        assertEq(game.village(bob).shieldUntil, arrival + 11 hours);
    }

    function testResolutionDuringShieldCancelsRaid() public {
        (uint256 id, uint256 arrival) = _raidWithShieldAtNominalArrival();
        vm.warp(arrival);
        vm.prank(bob);
        army.resolve(address(game), id);
        assertTrue(army.report(address(game), id).cancelled);
        assertEq(_sum(army.movement(address(game), id).loot), 0);
    }

    function testResolutionAfterShieldExpiryUsesCurrentProtection() public {
        (uint256 id, uint256 arrival) = _raidWithShieldAtNominalArrival();
        vm.warp(arrival + 12 hours);
        vm.prank(alice);
        army.resolve(address(game), id);
        Army.Report memory r = army.report(address(game), id);
        assertFalse(r.cancelled);
        assertTrue(r.decisive);
        assertGt(_sum(r.loot), 0);
    }
}
