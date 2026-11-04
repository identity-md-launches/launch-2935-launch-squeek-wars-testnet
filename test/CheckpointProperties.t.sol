// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameTest} from "./helpers/GameTest.sol";
import {SeedLedger} from "src/SeedLedger.sol";

contract CheckpointPropertiesTest is GameTest {
    /// @dev With neither player holding an NFT, scheduling claims must not alter either entitlement.
    /// This compares two public execution paths instead of duplicating the cumulative-index formula.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzzBatchedAndDailyClaimsGiveIdenticalSeedAndXP(uint16[8] memory deltas) public {
        uint256 dailySeed;
        uint256 dailyXP;
        bytes32 villagesBefore = keccak256(abi.encode(game.village(alice), game.village(bob)));
        for (uint256 i; i < deltas.length; ++i) {
            _checkpoint(deltas[i]);
            vm.prank(alice);
            (uint256 seed, uint256 xp) = game.claimSeed();
            dailySeed += seed;
            dailyXP += xp;
        }
        vm.prank(bob);
        (uint256 batchSeed, uint256 batchXP) = game.claimSeed();
        assertEq(batchSeed, dailySeed);
        assertEq(batchXP, dailyXP);
        assertEq(game.seedBalance(alice), game.seedBalance(bob));
        assertEq(army.champion(address(game), alice).xp, army.champion(address(game), bob).xp);
        assertEq(ledger.account(address(game), alice).cursor, deltas.length);
        assertEq(ledger.account(address(game), bob).cursor, deltas.length);
        assertEq(ledger.minted(address(game)), game.seedBalance(alice) + game.seedBalance(bob));
        assertEq(
            keccak256(abi.encode(game.village(alice), game.village(bob))),
            villagesBefore,
            "claiming SEED must not settle or alter resource balances"
        );
        vm.expectRevert(SeedLedger.NoClaim.selector);
        vm.prank(bob);
        game.claimSeed();
    }

    /// @dev Freeze past queries, append observations with different work, then re-query all levels.
    /// This exercises binary search across both exact checkpoints and points between checkpoints.
    /// forge-config: default.fuzz.runs = 512
    function testFuzzFutureObservationsCannotRewriteHistoricalWheelIntegrals(
        uint16[6] memory deltas,
        uint32[6] memory waits
    ) public {
        uint256[12] memory times;
        uint256[10][12] memory frozen;
        for (uint256 i; i < deltas.length; ++i) {
            _checkpoint(deltas[i]);
            uint256 start = vm.getBlockTimestamp();
            uint256 elapsed = bound(waits[i], 1, 12 hours);
            times[2 * i] = start;
            times[2 * i + 1] = start + elapsed;
            vm.warp(start + elapsed);
            for (uint8 level = 1; level <= 10; ++level) {
                uint256 atStart = ledger.wheelIntegral(level, start);
                uint256 atEnd = ledger.wheelIntegral(level, start + elapsed);
                frozen[2 * i][level - 1] = atStart;
                frozen[2 * i + 1][level - 1] = atEnd;
                assertGe(atEnd, atStart);
                assertLe(
                    atEnd - atStart,
                    elapsed * uint256(level) * U / 4,
                    "time-weighted bonus exceeded its level cap"
                );
                if (level > 1) assertGe(atEnd, frozen[2 * i + 1][level - 2]);
            }
        }
        // A long missed-day interval must not fabricate or backdate checkpoints.
        vm.warp(vm.getBlockTimestamp() + 31 days);
        ledger.checkpoint();
        assertEq(ledger.observationCount(), 8);
        assertEq(ledger.lastWork(), 0);
        for (uint256 i; i < times.length; ++i) {
            for (uint8 level = 1; level <= 10; ++level) {
                assertEq(
                    ledger.wheelIntegral(level, times[i]),
                    frozen[i][level - 1],
                    "later work rewrote an already-observed historical integral"
                );
            }
        }
    }

    function testMaximumWorkSaturatesEveryWheelLevelAndZeroWorkStopsAllGrowth() public {
        _checkpoint(type(uint64).max - core.work());
        uint256 start = vm.getBlockTimestamp();
        vm.warp(start + 1 hours);
        for (uint8 level = 1; level <= 10; ++level) {
            assertEq(ledger.wheelIntegral(level, start), 0, "work cannot boost earlier time");
            assertEq(ledger.wheelIntegral(level, start + 1 hours), uint256(level) * U / 4 * 1 hours);
        }
        _checkpoint(0);
        uint256 stop = vm.getBlockTimestamp();
        vm.warp(stop + 30 days);
        for (uint8 level = 1; level <= 10; ++level) {
            uint256 expected = uint256(level) * U / 4 * (stop - start);
            assertEq(ledger.wheelIntegral(level, stop), expected);
            assertEq(
                ledger.wheelIntegral(level, vm.getBlockTimestamp()),
                expected,
                "zero-work observation must stop the previous bonus"
            );
        }
        assertEq(ledger.wheelIntegral(0, vm.getBlockTimestamp()), 0);
        assertEq(ledger.wheelIntegral(10, START - 1), 0);
    }
}
