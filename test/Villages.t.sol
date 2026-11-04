// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameErrors as E} from "../src/libraries/GameErrors.sol";
import {GameTest} from "./helpers/GameTest.sol";
import {Villages} from "../src/Villages.sol";
import {SeedLedger} from "../src/SeedLedger.sol";
import {Clans} from "../src/Clans.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";

contract VillagesTest is GameTest {
    function testFoundingStartingState() public view {
        Villages.Village memory v = game.village(alice);
        assertEq(v.name, "Alice");
        assertEq(v.tile, game.tileForSlot(0));
        assertEq(v.shieldUntil, START + 7 days);
        assertEq(v.buildings[G.TH], 1);
        assertEq(v.buildings[G.WALLS], 1);
        for (uint8 i; i < 8; ++i) {
            assertEq(v.fields[i], 1);
        }
        for (uint8 i; i < 4; ++i) {
            assertEq(v.stock[i], 750 * U);
        }
        assertEq(game.tileOwner(v.tile), alice);
    }

    function testNamesUniqueCaseInsensitiveFinalAndWalletUnique() public {
        vm.expectRevert(E.NameTaken.selector);
        _found(carol, "aLiCe");
        vm.expectRevert(Villages.InvalidAction.selector);
        _found(alice, "Other");
        vm.expectRevert(E.InvalidNameLength.selector);
        _found(carol, "ab");
        vm.expectRevert(E.InvalidNameLength.selector);
        _found(carol, "abcdefghijklmnopq");
        vm.expectRevert(E.InvalidNameCharacter.selector);
        _found(carol, "bad name");
        vm.expectRevert(E.InvalidNameCharacter.selector);
        _found(carol, unicode"Squéek");
        _found(carol, "Carol_9");
        assertEq(game.village(carol).name, "Carol_9");
    }

    function testFoundingSkipsEveryFiftiethSlot() public {
        for (uint256 i = 2; i < 51; ++i) {
            _found(address(uint160(10000 + i)), string.concat("Player", vm.toString(i)));
        }
        assertEq(game.village(address(10000 + 48)).tile, game.tileForSlot(48));
        assertEq(game.village(address(10000 + 49)).tile, game.tileForSlot(50));
        assertEq(game.tileOwner(game.campTile(0)), address(0));
    }

    function testProductionAndCap() public {
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        uint256[4] memory amounts = game.stock(alice);
        for (uint8 i; i < 4; ++i) {
            assertEq(amounts[i], 786 * U);
        }
        game.sync(alice);
        vm.warp(vm.getBlockTimestamp() + 100 days);
        game.sync(alice);
        amounts = game.stock(alice);
        for (uint8 i; i < 4; ++i) {
            assertEq(amounts[i], 1500 * U);
        }
    }

    function testFuzzRepeatedSyncDoesNotDestroyFractionalProduction(uint32 elapsed) public {
        elapsed = uint32(bound(elapsed, 1, 10000));
        uint256 start = vm.getBlockTimestamp();
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(start + uint256(elapsed) * i / 10);
            game.sync(alice);
        }
        uint256[4] memory frequent = game.stock(alice);
        uint256[4] memory once = game.stock(bob);
        for (uint8 i; i < 4; ++i) {
            assertEq(frequent[i], once[i]);
        }
    }

    function testOrderCompleteAndCancelRefund() public {
        uint256 beforeSeed = game.seedBalance(alice);
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 0);
        Villages.BuildOrder memory order = game.buildOrder(alice, 0);
        assertEq(order.level, 2);
        assertEq(game.seedBalance(alice), beforeSeed - order.seed);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeBuild(alice, 0);
        vm.expectRevert(E.AlreadyBuildingTarget.selector);
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 1);
        uint256[4] memory beforeStock = game.stock(alice);
        vm.prank(alice);
        game.cancelBuild(0);
        uint256[4] memory afterStock = game.stock(alice);
        for (uint8 i; i < 4; ++i) {
            assertEq(afterStock[i], beforeStock[i] + order.cost[i] * 80 / 100);
        }
        assertEq(game.seedBalance(alice), beforeSeed - order.seed * 20 / 100);
        vm.expectRevert();
        vm.prank(alice);
        game.cancelBuild(0);
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 0);
        vm.warp(game.buildOrder(alice, 0).readyAt);
        vm.prank(outsider);
        game.completeBuild(alice, 0);
        assertEq(game.village(alice).buildings[G.TH], 2);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeBuild(alice, 0);
    }

    function testBuildSlotsPlotsAndResearchGates() public {
        vm.prank(alice);
        game.orderBuild(8 + G.BARRACKS, 0);
        vm.prank(alice);
        game.orderBuild(8 + G.ACADEMY, 1);
        vm.expectRevert();
        vm.prank(alice);
        game.orderBuild(8 + G.STORE, 0);
        uint256 ready = game.buildOrder(alice, 0).readyAt;
        vm.warp(ready);
        game.completeBuild(alice, 0);
        game.completeBuild(alice, 1);
        vm.expectRevert(E.NoPlotAvailable.selector);
        vm.prank(alice);
        game.orderBuild(8 + G.STORE, 0);
        vm.expectRevert(E.ResearchVaultFirst.selector);
        vm.prank(alice);
        game.orderBuild(8 + G.VAULT, 0);
        vm.expectRevert(E.ResearchTier2First.selector);
        vm.prank(alice);
        game.orderBuild(8 + G.FORGE, 0);
        vm.expectRevert(E.FieldCappedByTownHall.selector);
        vm.prank(alice);
        game.orderBuild(0, 0);
    }

    function testTwoPendingNewBuildingsCannotOverbookLastPlot() public {
        _build(alice, 8 + G.BARRACKS);
        vm.prank(alice);
        game.orderBuild(8 + G.ACADEMY, 0);
        vm.expectRevert(E.NoPlotAvailable.selector);
        vm.prank(alice);
        game.orderBuild(8 + G.STORE, 1);
    }

    function testBuildAndResearchCountersOnlyCompletedSpend() public {
        _build(alice, 8 + G.ACADEMY);
        Clans.Counters memory c = clans.counters(address(game), alice, false, 0);
        assertEq(c.build, 700 * U);
        assertEq(c.research, 0);
        vm.prank(alice);
        game.orderResearch();
        vm.expectRevert(Villages.NotReady.selector);
        game.completeResearch(alice);
        vm.expectRevert(E.ResearchBusy.selector);
        vm.prank(alice);
        game.orderResearch();
        vm.warp(game.study(alice).readyAt);
        game.completeResearch(alice);
        assertEq(game.village(alice).tier, 1);
        c = clans.counters(address(game), alice, false, 0);
        assertEq(c.research, 900 * U);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeResearch(alice);
        vm.expectRevert(E.AcademyTooLow.selector);
        vm.prank(alice);
        game.orderResearch();
    }

    function testMarketBurnsOnlyOwnInputAndCannotProduceSeed() public {
        _build(alice, 8 + G.MARKET);
        uint256[4] memory beforeStock = game.stock(alice);
        uint256[4] memory bobBefore = game.stock(bob);
        vm.prank(alice);
        game.exchange(0, 1, 2);
        uint256[4] memory afterStock = game.stock(alice);
        assertEq(afterStock[0], beforeStock[0] - 200 * U);
        assertEq(afterStock[1], beforeStock[1] + 50 * U);
        vm.prank(alice);
        game.exchange(4, 2, 1);
        assertEq(game.seedBalance(alice), 1400 * U);
        for (uint8 i; i < 4; ++i) {
            assertEq(game.stock(bob)[i], bobBefore[i]);
        }
        vm.expectRevert(E.InvalidExchange.selector);
        vm.prank(alice);
        game.exchange(0, 4, 1);
        vm.expectRevert(E.InvalidExchange.selector);
        vm.prank(alice);
        game.exchange(1, 1, 1);
        vm.expectRevert(E.InvalidExchange.selector);
        vm.prank(alice);
        game.exchange(0, 1, 0);
    }

    function testTreasuryBoostExpiryNoRetroactiveBonusAndNoStacking() public {
        vm.prank(alice);
        game.treasury(0, 0);
        vm.expectRevert(E.BoostActiveOrInvalidResource.selector);
        vm.prank(alice);
        game.treasury(0, 1);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertEq(game.stock(alice)[0], 795 * U);
        assertEq(game.stock(alice)[1], 786 * U);
        assertEq(game.seedBalance(alice), 1000 * U);
        vm.prank(alice);
        game.treasury(2, 0);
        vm.expectRevert(E.BannerAlreadyOwned.selector);
        vm.prank(alice);
        game.treasury(2, 0);
        assertTrue(game.village(alice).banner);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.sync(alice);
        assertLe(game.stock(alice)[0], 1500 * U);
    }

    function testPeaceShieldCooldown() public {
        _checkpoint(100_000);
        vm.prank(alice);
        game.claimSeed();
        vm.warp(START + 8 days);
        vm.prank(alice);
        game.treasury(1, 0);
        assertEq(game.village(alice).shieldUntil, vm.getBlockTimestamp() + 12 hours);
        vm.warp(vm.getBlockTimestamp() + 12 hours);
        vm.expectRevert(E.PeaceCooldown.selector);
        vm.prank(alice);
        game.treasury(1, 0);
        vm.warp(vm.getBlockTimestamp() + 60 hours);
        vm.prank(alice);
        game.treasury(1, 0);
        assertEq(game.village(alice).shieldUntil, vm.getBlockTimestamp() + 12 hours);
    }

    function testPeaceShieldRefusedWhileLongerShieldRunsAndChargesNothing() public {
        _checkpoint(100_000);
        vm.prank(alice);
        game.claimSeed();
        uint256 seed = game.seedBalance(alice);
        uint64 founding = game.village(alice).shieldUntil;
        vm.expectRevert(E.ShieldAlreadyActive.selector);
        vm.prank(alice);
        game.treasury(1, 0);
        assertEq(game.seedBalance(alice), seed);
        assertEq(game.village(alice).peaceUsedAt, 0);
        vm.warp(founding - 12 hours + 1);
        vm.prank(alice);
        game.treasury(1, 0);
        assertEq(game.seedBalance(alice), seed - 4000 * U);
        assertEq(game.village(alice).shieldUntil, vm.getBlockTimestamp() + 12 hours);
    }

    function testBuildSpeedSnapshotsCurrentNFTAtOrderAfterTransfer() public {
        _checkpoint(11000);
        nft.setBalance(alice, 1);
        vm.prank(alice);
        game.orderBuild(8 + G.BARRACKS, 0);
        uint64 ready = game.buildOrder(alice, 0).readyAt;
        assertEq(ready - vm.getBlockTimestamp(), 1836);
        nft.move(alice, bob);
        vm.prank(alice);
        game.orderBuild(8 + G.ACADEMY, 1);
        assertEq(game.buildOrder(alice, 1).readyAt - vm.getBlockTimestamp(), 2160);
        vm.prank(bob);
        game.orderBuild(8 + G.BARRACKS, 0);
        assertEq(game.buildOrder(bob, 0).readyAt - vm.getBlockTimestamp(), 1836);
        assertEq(game.buildOrder(alice, 0).readyAt, ready);
    }

    function testOnlyArmyCanUseAccountingCallbacks() public {
        uint256[4] memory values;
        vm.expectRevert(Villages.OnlyArmy.selector);
        game.armySpend(alice, values);
        vm.expectRevert(Villages.OnlyArmy.selector);
        game.armyCredit(alice, values);
        vm.expectRevert(Villages.OnlyArmy.selector);
        game.armyLoot(alice, 100 * U);
        vm.expectRevert(Villages.OnlyArmy.selector);
        game.armyDamageWalls(alice, 1);
        vm.expectRevert(Villages.OnlyArmy.selector);
        game.armyRecord(alice, 0, 1);
        vm.expectRevert(Villages.OnlyArmy.selector);
        game.armyTouch(alice);
    }

    function testUnfoundedWalletCannotAct() public {
        vm.startPrank(outsider);
        vm.expectRevert(Villages.NoVillage.selector);
        game.orderBuild(0, 0);
        vm.expectRevert(Villages.NoVillage.selector);
        game.orderResearch();
        vm.expectRevert(Villages.NoVillage.selector);
        game.claimSeed();
        vm.expectRevert(Villages.NoVillage.selector);
        game.train(0, 1);
        vm.expectRevert(Villages.NoVillage.selector);
        game.treasury(2, 0);
        vm.stopPrank();
    }

    function testNativeETHRejectedByEveryApplication() public {
        address[5] memory apps =
            [address(game), address(army), address(ledger), address(clans), address(rules)];
        vm.deal(address(this), 1 ether);
        for (uint256 i; i < apps.length; ++i) {
            (bool ok,) = apps[i].call{value: 1}("");
            assertFalse(ok);
            assertEq(apps[i].balance, 0);
        }
    }

    function testExternalNFTFailureRollsBackBuildAndBalanceChanges() public {
        nft.setBroken(true);
        uint256[4] memory beforeStock = game.stock(alice);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 0);
        assertEq(game.buildOrder(alice, 0).readyAt, 0);
        assertEq(game.seedBalance(alice), 1500 * U);
        for (uint8 i; i < 4; ++i) {
            assertEq(game.stock(alice)[i], beforeStock[i]);
        }
    }

    function testWheelhouseCheckpointDoesNotBoostPastProduction() public {
        _build(alice, 8 + G.WHEEL);
        uint256 boundary = (ledger.currentDay() + 1) * 1 days + 4 hours;
        vm.warp(boundary - 2 hours);
        vm.prank(alice);
        game.orderBuild(8 + G.BARRACKS, 0);
        uint256[4] memory before_ = game.stock(alice);
        vm.warp(boundary);
        core.setWork(core.work() + 4320);
        ledger.checkpoint();
        for (uint8 i; i < 4; ++i) {
            assertEq(game.stock(alice)[i], G.min(1500 * U, before_[i] + 72 * U));
        }
        vm.warp(boundary + 1 hours);
        for (uint8 i; i < 4; ++i) {
            assertEq(game.stock(alice)[i], G.min(1500 * U, before_[i] + 117 * U));
        }
    }

    function testTreasuryBoostStopsAtExpiryInsideUnsettledInterval() public {
        uint256[4] memory all = game.stock(alice);
        vm.prank(address(army));
        game.armySpend(alice, all);
        vm.prank(alice);
        game.treasury(0, 0);
        vm.warp(vm.getBlockTimestamp() + 25 hours);
        assertEq(game.stock(alice)[0], 1116 * U);
        assertEq(game.stock(alice)[1], 900 * U);
        game.sync(alice);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertEq(game.stock(alice)[0], 1152 * U);
    }

    function testMarketOverflowRevertsSEEDBurnAtomically() public {
        _build(alice, 8 + G.MARKET);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        uint256 seed = game.seedBalance(alice);
        vm.expectRevert(E.InsufficientStorage.selector);
        vm.prank(alice);
        game.exchange(4, 0, 1);
        assertEq(game.seedBalance(alice), seed);
        assertEq(game.stock(alice)[0], 1500 * U);
    }
}
