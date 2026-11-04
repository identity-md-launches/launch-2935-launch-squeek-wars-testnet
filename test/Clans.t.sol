// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameErrors as E} from "../src/libraries/GameErrors.sol";
import {EndgameTest} from "./helpers/EndgameTest.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";
import {Army} from "../src/Army.sol";
import {Clans} from "../src/Clans.sol";

contract ClansTest is EndgameTest {
    function _clanSetup() internal returns (uint256 id) {
        _advanceTo(alice, 4);
        _clanHall(alice, 3);
        _barracks(alice);
        _advanceTo(bob, 4);
        _clanHall(bob, 1);
        _barracks(bob);
        vm.prank(alice);
        id = game.foundClan("Hamsters");
        vm.prank(alice);
        game.inviteToClan(bob, true);
        vm.prank(bob);
        game.joinClan(id);
        vm.warp(vm.getBlockTimestamp() + 8 days);
    }

    function testFoundJoinLeaveGatesAndUniqueNames() public {
        vm.expectRevert(E.ClanHall3Required.selector);
        vm.prank(alice);
        game.foundClan("Hamsters");
        uint256 id = _clanSetup();
        assertEq(clans.clanOf(address(game), alice), id);
        assertEq(clans.clan(address(game), id).capacity, 9);
        assertTrue(clans.sameClan(address(game), alice, bob));
        vm.expectRevert(E.FounderLeavesLast.selector);
        vm.prank(alice);
        game.leaveClan();
        vm.prank(bob);
        game.leaveClan();
        assertFalse(clans.sameClan(address(game), alice, bob));
        vm.prank(alice);
        game.leaveClan();
        vm.expectRevert(E.ClanNameTaken.selector);
        vm.prank(alice);
        game.foundClan("hAMSTERS");
    }

    function testNoAttackInsideClanSupportOnlyAndRecallNoResourcesTransferred() public {
        _clanSetup();
        _troops(alice, 0, 10);
        uint256 aliceSeed = game.seedBalance(alice);
        uint256 bobSeed = game.seedBalance(bob);
        vm.expectRevert(E.TargetProtected.selector);
        _send(alice, bob, 0, 0, 1, false, 1);
        vm.expectRevert(E.InvalidSupport.selector);
        _send(alice, bob, 0, 0, 1, true, 3);
        uint256 id = _send(alice, bob, 0, 0, 6, false, 3);
        _arrive(id);
        assertEq(army.movement(address(game), id).mode, 5);
        assertEq(army.supportMovements(address(game), bob).length, 1);
        assertEq(army.home(address(game), alice)[0], 4);
        assertEq(army.home(address(game), bob)[0], 0);
        assertEq(game.seedBalance(alice), aliceSeed);
        assertEq(game.seedBalance(bob), bobSeed);
        vm.prank(bob);
        game.recall(id);
        _arrive(id);
        assertEq(army.home(address(game), alice)[0], 10);
        assertEq(army.supportMovements(address(game), bob).length, 0);
        assertEq(_sum(army.movement(address(game), id).loot), 0);
    }

    function testFormerClanSupportCanBeReturnedByAnyone() public {
        _clanSetup();
        _troops(alice, 0, 4);
        uint256 id = _send(alice, bob, 0, 0, 4, false, 3);
        _arrive(id);
        vm.expectRevert(E.SupportStillAllied.selector);
        army.returnFormerSupport(address(game), id);
        vm.prank(bob);
        game.leaveClan();
        vm.prank(outsider);
        army.returnFormerSupport(address(game), id);
        _arrive(id);
        assertEq(army.home(address(game), alice)[0], 4);
    }

    function testJoiningClanInFlightCancelsAttack() public {
        _clanSetup();
        _troops(alice, 0, 8);
        uint256 clanId = clans.clanOf(address(game), alice);
        vm.prank(bob);
        game.leaveClan();
        uint256 id = _send(alice, bob, 0, 0, 8, true, 1);
        // The first invitation was spent on joining; rejoining needs a new one.
        vm.expectRevert(E.NotInvited.selector);
        vm.prank(bob);
        game.joinClan(clanId);
        vm.prank(alice);
        game.inviteToClan(bob, true);
        vm.prank(bob);
        game.joinClan(clanId);
        _arrive(id);
        assertTrue(army.report(address(game), id).cancelled);
        _arrive(id);
        assertEq(army.home(address(game), alice)[0], 8);
    }

    function testSupportDefendsAndLossesReleaseOriginsRoom() public {
        _clanSetup();
        _troops(alice, 0, 10);
        _troops(bob, 0, 5);
        uint256 support = _send(alice, bob, 0, 0, 10, false, 3);
        _arrive(support);
        _found(carol, "Carol");
        _advanceTo(carol, 4);
        _barracks(carol);
        _burrow(carol, 4);
        _troops(carol, 0, 100);
        uint256 id = _send(carol, bob, 0, 0, 100, true, 1);
        _arrive(id);
        Army.Report memory r = army.report(address(game), id);
        assertTrue(r.decisive);
        assertEq(r.defenderLostValue, 15 * 180);
        assertEq(army.allocatedRoom(address(game), alice), 0);
        assertEq(army.allocatedRoom(address(game), bob), 0);
        assertEq(army.movement(address(game), support).units[0], 0);
        // An empty contingent must release its support slot immediately, just as recall does.
        assertEq(army.movement(address(game), support).mode, 4);
        assertEq(army.supportMovements(address(game), bob).length, 0);
        _troops(alice, 0, 5);
        uint256 replacement = _send(alice, bob, 0, 0, 5, false, 3);
        _arrive(replacement);
        assertEq(army.supportMovements(address(game), bob).length, 1);
        assertEq(army.movement(address(game), replacement).mode, 5);
        // Completing the old, empty return must neither free the new slot nor create troops.
        army.resolve(address(game), support);
        assertEq(army.movement(address(game), support).mode, 6);
        assertEq(army.home(address(game), alice)[0], 0);
        assertEq(army.allocatedRoom(address(game), alice), 5);
        vm.expectRevert(E.InvalidSupport.selector);
        _send(alice, bob, 0, 0, 1, false, 3);
    }

    function testClanCapacityAndFounderUpgrade() public {
        // Test the module's bounded membership independently in this test's namespace.
        uint256 id = clans.found(alice, "Capacity", 3);
        for (uint256 i; i < 8; ++i) {
            clans.invite(alice, address(uint160(2000 + i)), true);
            clans.join(address(uint160(2000 + i)), id, 1);
        }
        clans.invite(alice, carol, true);
        vm.expectRevert(E.ClanFullOrMissing.selector);
        clans.join(carol, id, 1);
        vm.expectRevert(E.CannotRaiseCapacity.selector);
        clans.raiseCapacity(bob, 4);
        clans.raiseCapacity(alice, 4);
        clans.join(carol, id, 1);
        assertEq(clans.clan(address(this), id).members.length, 10);
    }

    function testUninvitedJoinRevertsAndCannotCancelRaid() public {
        _advanceTo(alice, 4);
        _clanHall(alice, 3);
        _barracks(alice);
        _advanceTo(bob, 4);
        _clanHall(bob, 1);
        vm.prank(alice);
        uint256 clanId = game.foundClan("Hamsters");
        vm.warp(vm.getBlockTimestamp() + 8 days);
        _troops(alice, 0, 8);
        uint256 id = _send(alice, bob, 0, 0, 8, false, 1);
        vm.expectRevert(E.NotInvited.selector);
        vm.prank(bob);
        game.joinClan(clanId);
        assertFalse(clans.sameClan(address(game), alice, bob));
        _arrive(id);
        Army.Report memory r = army.report(address(game), id);
        assertFalse(r.cancelled);
        assertEq(r.attack, 320);
    }

    function testOnlyFounderInvitesAndRevokedInvitationCannotJoin() public {
        _advanceTo(alice, 4);
        _clanHall(alice, 3);
        _advanceTo(bob, 4);
        _clanHall(bob, 1);
        vm.prank(alice);
        uint256 id = game.foundClan("Hamsters");
        vm.expectRevert(E.OnlyFounderInvites.selector);
        vm.prank(bob);
        game.inviteToClan(bob, true);
        vm.expectRevert(abi.encodeWithSignature("NoVillage()"));
        vm.prank(outsider);
        game.inviteToClan(bob, true);
        vm.prank(alice);
        game.inviteToClan(bob, true);
        assertTrue(clans.invited(address(game), id, bob));
        vm.prank(alice);
        game.inviteToClan(bob, false);
        vm.expectRevert(E.NotInvited.selector);
        vm.prank(bob);
        game.joinClan(id);
        vm.prank(alice);
        game.inviteToClan(bob, true);
        vm.prank(bob);
        game.joinClan(id);
        assertFalse(clans.invited(address(game), id, bob));
        // A member who is not the founder cannot admit anyone either.
        vm.expectRevert(E.OnlyFounderInvites.selector);
        vm.prank(bob);
        game.inviteToClan(carol, true);
    }

    function testRankingFormulaWeekIsolationAndCanonicalNamespace() public {
        clans.record(alice, 0, 10000 * U);
        clans.record(alice, 1, 2000 * U);
        clans.record(alice, 2, 5000);
        clans.record(alice, 3, 5000);
        assertEq(clans.overall(address(this), alice, false, 0), 170);
        assertEq(clans.overall(address(game), alice, false, 0), 0);
        uint256 w = clans.week();
        assertEq(clans.overall(address(this), alice, true, w), 170);
        vm.warp(vm.getBlockTimestamp() + 7 days);
        clans.record(alice, 0, 100 * U);
        clans.record(alice, 2, 50000);
        assertEq(clans.overall(address(this), alice, true, w), 170);
        assertEq(clans.overall(address(this), alice, true, w + 1), 2);
        assertEq(clans.overall(address(this), alice, false, 0), 222);
    }
}
