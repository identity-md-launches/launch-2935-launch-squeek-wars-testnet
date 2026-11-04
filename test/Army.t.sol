// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameErrors as E} from "../src/libraries/GameErrors.sol";
import {GameTest} from "./helpers/GameTest.sol";
import {EndgameTest} from "./helpers/EndgameTest.sol";
import {Army} from "../src/Army.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";
import {Clans} from "../src/Clans.sol";
import {SeedLedger} from "../src/SeedLedger.sol";

contract ArmyTest is GameTest {
    function testTrainingCostsReservationQueueAndPermissionlessFinish() public {
        _build(alice, 8 + G.BARRACKS);
        uint256[4] memory before_ = game.stock(alice);
        vm.prank(alice);
        game.train(0, 3);
        assertEq(army.allocatedRoom(address(game), alice), 3);
        assertEq(game.stock(alice)[0], before_[0] - 150 * U);
        vm.expectRevert(E.TrainingBusyOrMissingVillage.selector);
        vm.prank(alice);
        game.train(0, 1);
        vm.expectRevert(E.TrainingNotReady.selector);
        army.completeTraining(address(game), alice);
        vm.warp(army.training(address(game), alice).readyAt);
        vm.prank(outsider);
        army.completeTraining(address(game), alice);
        assertEq(army.home(address(game), alice)[0], 3);
        vm.expectRevert(E.TrainingNotReady.selector);
        army.completeTraining(address(game), alice);
    }

    function testTrainingRejectsLockedUnitsTooManyOrMissingBarracks() public {
        vm.expectRevert();
        vm.prank(alice);
        game.train(0, 1);
        _build(alice, 8 + G.BARRACKS);
        vm.expectRevert(E.ResearchRequired.selector);
        vm.prank(alice);
        game.train(1, 1);
        vm.expectRevert(E.InsufficientBurrowRoom.selector);
        vm.prank(alice);
        game.train(0, 31);
        vm.expectRevert();
        vm.prank(alice);
        game.train(0, 0);
    }

    function testUpkeepChargedForCommittedRoom() public {
        _build(alice, 8 + G.BARRACKS);
        vm.prank(alice);
        game.train(0, 4);
        uint256 food = game.stock(alice)[1];
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertEq(game.stock(alice)[1], food + 34 * U);
    }

    function testShieldNoEarlyResolveReturnOnceAndRoomConservation() public {
        _build(alice, 8 + G.BARRACKS);
        _train(alice, 0, 8);
        vm.expectRevert(E.TargetProtected.selector);
        _send(alice, bob, 0, 0, 8, true, 1);
        vm.warp(START + 8 days);
        uint256 id = _send(alice, bob, 0, 0, 8, true, 1);
        assertEq(army.home(address(game), alice)[0], 0);
        assertTrue(army.champion(address(game), alice).away);
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), id);
        uint256 targetSeed = game.seedBalance(bob);
        uint256 attackerSeed = game.seedBalance(alice);
        _arrive(id);
        Army.Movement memory returning = army.movement(address(game), id);
        assertEq(returning.mode, 4);
        assertTrue(army.report(address(game), id).decisive);
        uint256 carried = _sum(returning.loot);
        assertGt(carried, 0);
        assertEq(game.seedBalance(bob), targetSeed);
        assertEq(game.seedBalance(alice), attackerSeed);
        assertEq(army.allocatedRoom(address(game), alice), returning.units[0]);
        _arrive(id);
        assertEq(army.movement(address(game), id).mode, 6);
        assertEq(army.home(address(game), alice)[0], returning.units[0]);
        assertFalse(army.champion(address(game), alice).away);
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), id);
    }

    function testAttackingBreaksOwnShieldAndCannotReuseDeployedTroopsOrChampion() public {
        _build(alice, 8 + G.BARRACKS);
        _train(alice, 0, 8);
        _send(alice, address(0), 0, 0, 4, true, 1);
        assertEq(game.village(alice).shieldUntil, vm.getBlockTimestamp());
        vm.expectRevert(E.ChampionAway.selector);
        _send(alice, address(0), 1, 0, 4, true, 1);
        vm.expectRevert(E.InsufficientTroops.selector);
        _send(alice, address(0), 1, 0, 5, false, 1);
        vm.expectRevert(E.InvalidMovement.selector);
        _send(alice, alice, 0, 0, 1, false, 1);
    }

    function testShieldBoughtInFlightSafelyReturnsTroopsWithoutLoot() public {
        _build(alice, 8 + G.BARRACKS);
        _train(alice, 0, 8);
        _checkpoint(100000);
        vm.prank(bob);
        game.claimSeed();
        vm.warp(START + 8 days);
        uint256 id = _send(alice, bob, 0, 0, 8, true, 1);
        // Buy immediately before arrival, so all destinations including long journeys are covered.
        vm.warp(army.movement(address(game), id).arriveAt - 1);
        vm.prank(bob);
        game.treasury(1, 0);
        _arrive(id);
        assertTrue(army.report(address(game), id).cancelled);
        assertEq(_sum(army.movement(address(game), id).loot), 0);
        _arrive(id);
        assertEq(army.home(address(game), alice)[0], 8);
    }

    function testRaidLimitCountsDeparturesAndHasDailyReset() public {
        _build(alice, 8 + G.BARRACKS);
        _train(alice, 0, 8);
        for (uint8 i; i < 3; ++i) {
            _send(alice, address(0), 0, 0, 1, false, 1);
        }
        vm.expectRevert(E.DailyRaidLimit.selector);
        _send(alice, address(0), 0, 0, 1, false, 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _send(alice, address(0), 0, 0, 1, false, 1);
    }

    function testOutsiderNamespaceCannotModifyCanonicalTroopsXPOrStats() public {
        army.creditXP(alice, 1000000);
        army.allocate(alice, 10, 0, 0, 0);
        assertEq(army.champion(address(game), alice).xp, 0);
        assertEq(army.champion(address(game), alice).might, 0);
        vm.expectRevert();
        army.train(alice, 0, 1);
        vm.expectRevert();
        army.recall(alice, 1);
    }

    function testNFTLossChangesChampionStatsImmediately() public {
        _checkpoint(1_000_000);
        vm.prank(alice);
        game.claimSeed();
        vm.prank(alice);
        game.allocateChampion(1, 1, 1, 1);
        (uint256 m, uint256 a, uint256 d, uint256 c) = army.championStats(address(game), alice);
        assertEq(m, 75);
        assertEq(a, 5000);
        assertEq(d, 5000);
        assertEq(c, 10000);
        nft.setBalance(alice, 1);
        (m, a, d, c) = army.championStats(address(game), alice);
        assertEq(m, 82);
        assertEq(a, 5500);
        assertEq(d, 5500);
        assertEq(c, 11000);
        nft.move(alice, bob);
        (m, a, d, c) = army.championStats(address(game), alice);
        assertEq(m, 75);
        assertEq(a, 5000);
        assertEq(d, 5000);
        assertEq(c, 10000);
    }

    function testChampionPointCapsNoRespecAndLevelCap() public {
        vm.prank(address(game));
        army.creditXP(alice, 1_000_000);
        assertEq(army.championLevel(address(game), alice), 30);
        vm.prank(alice);
        game.allocateChampion(56, 20, 20, 20);
        vm.expectRevert(E.InsufficientChampionPoints.selector);
        vm.prank(alice);
        game.allocateChampion(57, 20, 20, 20);
        vm.expectRevert(E.StatCap.selector);
        vm.prank(alice);
        game.allocateChampion(56, 21, 20, 20);
        vm.expectRevert(E.PointsCannotBeReassigned.selector);
        vm.prank(alice);
        game.allocateChampion(55, 20, 20, 20);
    }

    function testOracleFailureLeavesMovementResolvable() public {
        _build(alice, 8 + G.BARRACKS);
        _train(alice, 0, 8);
        uint256 id = _send(alice, address(0), 0, 0, 8, true, 1);
        vm.warp(army.movement(address(game), id).arriveAt);
        nft.setBroken(true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        army.resolve(address(game), id);
        assertEq(army.movement(address(game), id).mode, 1);
        nft.setBroken(false);
        army.resolve(address(game), id);
        assertEq(army.movement(address(game), id).mode, 4);
    }
}

contract LateGameArmyTest is EndgameTest {
    function testBattleKilledValueVaultAndLootConservation() public {
        _advanceTo(alice, 4);
        _barracks(alice);
        _burrow(alice, 4);
        _troops(alice, 0, 80);
        _advanceTo(bob, 4);
        _barracks(bob);
        _research(bob, 1);
        _fundedBuild(bob, 8 + G.VAULT);
        _troops(bob, 0, 5);
        vm.warp(vm.getBlockTimestamp() + 8 days);
        uint256 id = _send(alice, bob, 0, 0, 80, true, 1);
        vm.warp(army.movement(address(game), id).arriveAt);
        uint256[4] memory beforeStock = game.stock(bob);
        army.resolve(address(game), id);
        Army.Report memory r = army.report(address(game), id);
        assertTrue(r.decisive);
        assertEq(r.defenderLostValue, 900);
        assertEq(army.home(address(game), bob)[0], 0);
        for (uint8 i; i < 4; ++i) {
            assertEq(game.stock(bob)[i] + r.loot[i], beforeStock[i]);
            assertGe(game.stock(bob)[i], game.vaultProtection(bob));
        }
        Clans.Counters memory c = clans.counters(address(game), alice, false, 0);
        assertEq(c.attack, 900);
        assertEq(c.loot, _sum(r.loot));
        assertEq(army.allocatedRoom(address(game), bob), 0);
        assertEq(army.allocatedRoom(address(game), alice), army.movement(address(game), id).units[0]);
    }

    function testWeakTargetHalfLootAndNoCombatPointsOrXP() public {
        _advanceTo(alice, 4);
        _barracks(alice);
        _troops(alice, 0, 20);
        _barracks(bob);
        _troops(bob, 0, 1);
        vm.warp(vm.getBlockTimestamp() + 8 days);
        uint256 xpBefore = army.champion(address(game), alice).xp;
        uint256 id = _send(alice, bob, 0, 0, 20, true, 1);
        _arrive(id);
        Army.Movement memory m = army.movement(address(game), id);
        assertTrue(army.report(address(game), id).decisive);
        assertEq(_sum(m.loot), uint256(m.units[0]) * 50 * U / 2);
        assertEq(clans.counters(address(game), alice, false, 0).attack, 0);
        assertEq(army.champion(address(game), alice).xp, xpBefore);
    }

    function testScoutThenRaidReceivesTenPercentAndScoutsAloneEnforced() public {
        _advanceTo(alice, 4);
        _research(alice, 2);
        _barracks(alice);
        _burrow(alice, 2);
        _troops(alice, 6, 2);
        _troops(alice, 0, 20);
        vm.warp(vm.getBlockTimestamp() + 8 days);
        vm.expectRevert(E.OnlyScoutsReconnoitre.selector);
        _send(alice, bob, 0, 0, 1, false, 2);
        uint256 recon = _send(alice, bob, 0, 6, 2, false, 2);
        _arrive(recon);
        assertEq(army.scoutedUntil(address(game), alice, bob), vm.getBlockTimestamp() + 12 hours);
        uint256 id = _send(alice, bob, 0, 0, 20, false, 1);
        // Choose the same dispatch time so the bonus must still be valid on arrival only if travel <=12h.
        uint256 arrive = army.movement(address(game), id).arriveAt;
        bool active = arrive < army.scoutedUntil(address(game), alice, bob);
        _arrive(id);
        assertEq(army.report(address(game), id).attack, active ? 880 : 800);
    }

    function testCampRegrowthCapAndNoVault() public {
        _advanceTo(alice, 4);
        _barracks(alice);
        _burrow(alice, 4);
        _troops(alice, 0, 100);
        uint256 id = _send(alice, address(0), 0, 0, 100, true, 1);
        _arrive(id);
        Army.Camp memory c = army.camp(address(game), 0);
        assertTrue(army.report(address(game), id).decisive);
        assertEq(c.defense, 0);
        assertEq(c.regrowAt, vm.getBlockTimestamp() + 24 hours);
        assertGt(_sum(army.movement(address(game), id).loot), 0);
        _arrive(id);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        uint32 soldiers = army.home(address(game), alice)[0];
        id = _send(alice, address(0), 0, 0, soldiers, true, 1);
        _arrive(id);
        assertGt(army.report(address(game), id).defense, 0);
        (, uint256 rate) = army.campParameters(0);
        c = army.camp(address(game), 0);
        for (uint8 i; i < 4; ++i) {
            assertLe(c.stock[i], rate * 24);
        }
    }

    function testCatapultWallsDamageMaximumTwoAndPassiveRepair() public {
        _advanceTo(alice, 10);
        _research(alice, 4);
        _barracks(alice);
        _burrow(alice, 10);
        _troops(alice, 5, 60);
        _troops(alice, 0, 100);
        _advanceTo(bob, 4);
        for (uint8 i = 1; i < 4; ++i) {
            _fundedBuild(bob, 8 + G.WALLS);
        }
        uint32[7] memory units;
        units[0] = 100;
        units[5] = 60;
        vm.prank(alice);
        uint256 id = game.send(bob, 0, units, true, 1);
        _arrive(id);
        assertTrue(army.report(address(game), id).decisive);
        assertEq(game.effectiveWalls(bob), 2);
        vm.warp(vm.getBlockTimestamp() + 12 hours - 1);
        assertEq(game.effectiveWalls(bob), 2);
        vm.warp(vm.getBlockTimestamp() + 1);
        assertEq(game.effectiveWalls(bob), 3);
        vm.warp(vm.getBlockTimestamp() + 12 hours);
        assertEq(game.effectiveWalls(bob), 4);
    }

    function testMaximumArmyAndChampionCombatDoesNotOverflow() public {
        _advanceTo(alice, 10);
        _research(alice, 5);
        _barracks(alice);
        _burrow(alice, 10);
        vm.prank(address(game));
        army.creditXP(alice, 1_000_000_000);
        vm.prank(alice);
        game.allocateChampion(56, 20, 20, 20);
        nft.setBalance(alice, type(uint256).max);
        uint32 count = uint32(game.roomCapacity(alice));
        // Per-resource capacity supports the entire maximum room allocation at Storehouse 18.
        _troops(alice, 0, count);
        assertEq(army.allocatedRoom(address(game), alice), game.roomCapacity(alice));
        uint256 id = _send(alice, address(0), 199, 0, count, true, 1);
        _arrive(id);
        _arrive(id);
        assertLe(army.allocatedRoom(address(game), alice), game.roomCapacity(alice));
        for (uint8 i; i < 4; ++i) {
            assertLe(game.stock(alice)[i], game.storageCapacity(alice));
        }
    }
}
