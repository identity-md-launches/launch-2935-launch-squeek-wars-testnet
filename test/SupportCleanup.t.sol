// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameTest} from "./helpers/GameTest.sol";
import {ArmyWorld} from "./helpers/ArmyWorld.sol";
import {Army} from "../src/Army.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";
import {GameErrors as E} from "../src/libraries/GameErrors.sol";
import {Vm} from "forge-std/Vm.sol";

contract SupportCleanupTest is GameTest {
    ArmyWorld private world;

    function setUp() public override {
        super.setUp();
        world = new ArmyWorld(army);
        _configure(alice, 0);
        _configure(bob, 1);
        _configure(carol, 2);
        _configure(outsider, 3);
    }

    function _configure(address who, uint16 tile) private {
        world.configure(who, G.Context(true, tile, 1, 1, 0, 1, 0, 4_000_000, 0));
    }

    function _clan() private returns (uint256 id) {
        vm.prank(address(world));
        id = clans.found(bob, "Supporters", 10);
    }

    function _join(address who, uint256 id) private {
        vm.prank(address(world));
        clans.invite(bob, who, true);
        vm.prank(address(world));
        clans.join(who, id, 1);
    }

    function _trainWorld(address who, uint32 count) private {
        world.train(who, 0, count);
        vm.warp(army.training(address(world), who).readyAt);
        army.completeTraining(address(world), who);
    }

    function _sendSupport(address who, uint32 count) private returns (uint256 id) {
        uint32[7] memory units;
        units[0] = count;
        vm.prank(address(world));
        id = army.send(who, bob, 0, units, false, 3);
    }

    function _resolve(uint256 id) private {
        vm.warp(army.movement(address(world), id).arriveAt);
        army.resolve(address(world), id);
    }

    function _raid(uint32 count) private returns (uint256 id) {
        _trainWorld(alice, count);
        uint32[7] memory units;
        units[0] = count;
        id = world.send(alice, bob, units, false);
        _resolve(id);
    }

    function testNondecisiveLossClearsOnlyEmptyContingent() public {
        uint256 clanId = _clan();
        _join(carol, clanId);
        _join(outsider, clanId);
        _trainWorld(carol, 1);
        uint256 empty = _sendSupport(carol, 1);
        _resolve(empty);
        _trainWorld(outsider, 100);
        uint256 surviving = _sendSupport(outsider, 100);
        _resolve(surviving);
        vm.recordLogs();
        uint256 raid = _raid(20);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool returned;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(army)
                    && logs[i].topics[0] == keccak256("MovementResolved(address,uint256,uint8,uint256)")
                    && uint256(logs[i].topics[2]) == empty
            ) {
                (uint8 mode, uint256 arrival) = abi.decode(logs[i].data, (uint8, uint256));
                assertEq(mode, 4);
                assertEq(arrival, army.movement(address(world), empty).arriveAt);
                assertFalse(returned, "duplicate cleanup event");
                returned = true;
            }
        }
        assertTrue(returned, "empty return must emit the existing movement event");
        assertFalse(army.report(address(world), raid).decisive);
        assertEq(army.movement(address(world), empty).mode, 4);
        assertEq(army.allocatedRoom(address(world), carol), 0);
        uint256[] memory list = army.supportMovements(address(world), bob);
        assertEq(list.length, 1);
        assertEq(list[0], surviving);
        Army.Movement memory survivor = army.movement(address(world), surviving);
        assertEq(survivor.mode, 5);
        assertGt(survivor.units[0], 0);
        assertEq(army.allocatedRoom(address(world), outsider), survivor.units[0]);
        _trainWorld(carol, 1);
        _sendSupport(carol, 1); // Pair released before the old empty return is resolved.
        vm.expectRevert(E.InvalidSupport.selector);
        _sendSupport(outsider, 1); // Surviving pair is still reserved.
    }

    function testFullSupportListWipeFreesAllAlliedSlotsAndPreservesFormerAlly() public {
        // A former clanmate occupies one slot; the current 30-member clan fills the other 29.
        vm.prank(address(world));
        uint256 oldClan = clans.found(outsider, "Former", 3);
        vm.prank(address(world));
        clans.invite(outsider, bob, true);
        vm.prank(address(world));
        clans.join(bob, oldClan, 1);
        _trainWorld(outsider, 5);
        uint256 former = _sendSupport(outsider, 5);
        _resolve(former);
        vm.prank(address(world));
        clans.leave(bob);
        uint256 clanId = _clan();
        uint256[29] memory supportIds;
        for (uint256 i; i < 29; ++i) {
            address who = address(uint160(0xB000 + i));
            _configure(who, 2);
            _join(who, clanId);
            _trainWorld(who, 5);
            supportIds[i] = _sendSupport(who, 5);
            _resolve(supportIds[i]);
        }
        assertEq(army.supportMovements(address(world), bob).length, 30);
        uint256 raid = _raid(10_000);
        Army.Report memory report_ = army.report(address(world), raid);
        assertTrue(report_.decisive);
        assertEq(report_.defenderLostValue, 29 * 5 * 180);
        uint256[] memory list = army.supportMovements(address(world), bob);
        assertEq(list.length, 1);
        assertEq(list[0], former);
        assertEq(army.movement(address(world), former).mode, 5);
        assertEq(army.movement(address(world), former).units[0], 5);
        assertEq(army.allocatedRoom(address(world), outsider), 5);
        for (uint256 i; i < 29; ++i) {
            Army.Movement memory m = army.movement(address(world), supportIds[i]);
            assertEq(m.mode, 4);
            assertEq(m.arriveAt, vm.getBlockTimestamp() + m.travelTime);
            assertEq(army.allocatedRoom(address(world), m.owner), 0);
            for (uint256 j; j < 7; ++j) {
                assertEq(m.units[j], 0);
            }
        }
        address first = address(0xB000);
        _trainWorld(first, 5);
        uint256 replacement = _sendSupport(first, 5);
        _resolve(replacement);
        assertEq(army.movement(address(world), replacement).mode, 5);
        assertEq(army.supportMovements(address(world), bob).length, 2);
        for (uint256 i; i < 29; ++i) {
            army.resolve(address(world), supportIds[i]);
        }
        assertEq(army.supportMovements(address(world), bob).length, 2);
        assertEq(army.home(address(world), first)[0], 0);
        assertEq(army.allocatedRoom(address(world), first), 5);
    }
}
