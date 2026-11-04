// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameTest} from "./helpers/GameTest.sol";
import {GameTypes as G} from "src/libraries/GameTypes.sol";
import {GameErrors as E} from "src/libraries/GameErrors.sol";
import {Villages} from "src/Villages.sol";
import {SeedLedger} from "src/SeedLedger.sol";

contract DispatchAtomicityTest is GameTest {
    function setUp() public override {
        super.setUp();
        _build(alice, 8 + G.BARRACKS);
        _train(alice, 0, 10);
    }

    function _state() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                game.village(alice),
                army.home(address(game), alice),
                army.allocatedRoom(address(game), alice),
                army.training(address(game), alice),
                army.champion(address(game), alice),
                army.movementCount(address(game)),
                ledger.account(address(game), alice),
                ledger.minted(address(game)),
                ledger.burned(address(game))
            )
        );
    }

    function _useAllThreeRaids(uint16 campId) private {
        for (uint256 i; i < 3; ++i) {
            _send(alice, address(0), campId, 0, 1, false, 1);
        }
        bytes32 before_ = _state();
        vm.expectRevert(E.DailyRaidLimit.selector);
        _send(alice, address(0), campId, 0, 1, false, 1);
        assertEq(_state(), before_, "fourth raid rejection changed game state");
    }

    function testRejectedDispatchAfterPartialTroopDebitsRestoresTroopsShieldAndRaidAllowance() public {
        uint32[7] memory units;
        units[0] = 1; // Debited first.
        units[6] = 1; // Rejected at the last troop type: no Scout exists.
        bytes32 before_ = _state();
        for (uint256 i; i < 5; ++i) {
            vm.expectRevert(E.InsufficientTroops.selector);
            vm.prank(alice);
            game.send(address(0), 0, units, true, 1);
            assertEq(_state(), before_, "late troop rejection was not atomic");
        }
        _useAllThreeRaids(0);
        assertEq(army.home(address(game), alice)[0], 7);
        assertEq(army.allocatedRoom(address(game), alice), 10);
        assertEq(army.movementCount(address(game)), 3);
    }

    function testChampionAwayFailureDoesNotConsumeAnotherCampsRaidAllowance() public {
        uint256 first = _send(alice, address(0), 1, 0, 1, true, 1);
        bytes32 firstMovement = keccak256(abi.encode(army.movement(address(game), first)));
        bytes32 before_ = _state();
        for (uint256 i; i < 5; ++i) {
            vm.expectRevert(E.ChampionAway.selector);
            _send(alice, address(0), 2, 0, 1, true, 1);
            assertEq(_state(), before_);
            assertEq(keccak256(abi.encode(army.movement(address(game), first))), firstMovement);
        }
        _useAllThreeRaids(2);
        assertEq(army.home(address(game), alice)[0], 6);
        assertTrue(army.champion(address(game), alice).away);
        assertEq(army.movementCount(address(game)), 4);
    }

    function testEmptyRaidCannotSpendTheDepartureQuota() public {
        uint32[7] memory empty;
        bytes32 before_ = _state();
        for (uint256 i; i < 5; ++i) {
            vm.expectRevert(E.InvalidTroopCount.selector);
            vm.prank(alice);
            game.send(address(0), 3, empty, false, 1);
            assertEq(_state(), before_);
        }
        _useAllThreeRaids(3);
    }

    function testForgedNamespaceCannotRouteArmyCallbacksIntoCanonicalVillage() public {
        bytes32 before_ = _state();
        // Anyone may create their own module namespace, but it has no canonical movement.
        army.creditXP(alice, 100_000);
        army.allocate(alice, 10, 1, 1, 1);
        assertEq(_state(), before_);
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), 1);
        assertEq(_state(), before_);
        vm.expectRevert(E.TrainingNotReady.selector);
        army.completeTraining(address(game), alice);
        assertEq(_state(), before_);
        vm.expectRevert(E.SupportStillAllied.selector);
        army.returnFormerSupport(address(game), 1);
        assertEq(_state(), before_);
    }
}

contract ConstructionRoundTripTest is GameTest {
    event BuildCancelled(address indexed player, uint8 indexed slot);

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzRepeatedOrderCancelLosesOnlyFeeAndCannotFarmRanking(
        uint8 choice,
        uint8 repetitions,
        uint8 slot
    ) public {
        _checkpoint(100_000);
        vm.prank(alice);
        game.claimSeed();
        _build(alice, 8 + G.TH);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        game.sync(alice);
        uint8[16] memory targets = [
            uint8(0),
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8 + G.TH,
            8 + G.WALLS,
            8 + G.WHEEL,
            8 + G.STORE,
            8 + G.BURROW,
            8 + G.BARRACKS,
            8 + G.ACADEMY,
            8 + G.MARKET
        ];
        uint8 target = targets[choice % targets.length];
        slot %= 2;
        uint256 cycles = bound(repetitions, 1, 5);
        Villages.Village memory original = game.village(alice);
        bytes32 ranks = keccak256(
            abi.encode(
                clans.counters(address(game), alice, false, 0),
                clans.counters(address(game), alice, true, clans.week())
            )
        );
        bytes32 bystander = keccak256(abi.encode(game.village(bob), game.seedBalance(bob)));
        uint256 minted = ledger.minted(address(game));
        for (uint256 k; k < cycles; ++k) {
            uint256[4] memory stockBefore = game.stock(alice);
            uint256 seedBefore = game.seedBalance(alice);
            uint256 burnedBefore = ledger.burned(address(game));
            vm.prank(alice);
            game.orderBuild(target, slot);
            Villages.BuildOrder memory order = game.buildOrder(alice, slot);
            vm.expectEmit(true, true, false, true, address(game));
            emit BuildCancelled(alice, slot);
            vm.prank(alice);
            game.cancelBuild(slot);
            uint256[4] memory after_ = game.stock(alice);
            for (uint256 r; r < 4; ++r) {
                // Retain ceil(20% of the cost). No clock tick, output or storage clipping occurs.
                assertEq(stockBefore[r] - after_[r], (order.cost[r] + 4) / 5);
            }
            uint256 seedFee = (order.seed + 4) / 5;
            assertEq(seedBefore - game.seedBalance(alice), seedFee);
            assertEq(ledger.burned(address(game)) - burnedBefore, seedFee);
            assertEq(game.buildOrder(alice, slot).readyAt, 0);
            assertEq(game.buildOrder(alice, 1 - slot).readyAt, 0);
        }
        Villages.Village memory afterVillage = game.village(alice);
        assertEq(
            keccak256(abi.encode(afterVillage.fields, afterVillage.buildings)),
            keccak256(abi.encode(original.fields, original.buildings))
        );
        assertEq(ledger.minted(address(game)), minted);
        assertEq(
            keccak256(
                abi.encode(
                    clans.counters(address(game), alice, false, 0),
                    clans.counters(address(game), alice, true, clans.week())
                )
            ),
            ranks,
            "cancelled spend cannot become season or weekly points"
        );
        assertEq(keccak256(abi.encode(game.village(bob), game.seedBalance(bob))), bystander);
        vm.expectRevert(E.CannotCancelCompletedBuild.selector);
        vm.prank(alice);
        game.cancelBuild(slot);
    }

    function testRejectedFoundingDoesNotReserveNameTileOrSeedAndCanRetrySameName() public {
        uint256 count = game.villageCount();
        uint16 tile = game.tileForSlot(count + count / 49);
        uint256 minted = ledger.minted(address(game));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        core.setBroken(true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        _found(carol, "RetryVillage");
        assertEq(game.villageCount(), count);
        assertEq(game.nameOwner(keccak256("retryvillage")), address(0));
        assertEq(game.tileOwner(tile), address(0));
        assertEq(game.village(carol).foundedAt, 0);
        assertFalse(ledger.account(address(game), carol).exists);
        assertEq(ledger.minted(address(game)), minted);
        core.setBroken(false);
        _found(carol, "RetryVillage");
        assertEq(game.villageCount(), count + 1);
        assertEq(game.nameOwner(keccak256("retryvillage")), carol);
        assertEq(game.tileOwner(tile), carol);
        assertEq(game.seedBalance(carol), 1500 * U);
    }
}
