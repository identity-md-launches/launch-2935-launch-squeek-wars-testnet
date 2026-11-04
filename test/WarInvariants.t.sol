// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {EndgameTest} from "./helpers/EndgameTest.sol";
import {MockCore} from "./helpers/Mocks.sol";
import {Villages} from "../src/Villages.sol";
import {Army} from "../src/Army.sol";
import {Clans} from "../src/Clans.sol";
import {SeedLedger} from "../src/SeedLedger.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";

/// @notice Drives three villages through village-vs-village raids, scouting, clan support, recalls,
/// clan churn, peace shields, checkpoints and claims. Every step snapshots all three villages and
/// checks that resources move between villages only as the loot the resolved battle reports, and
/// that SEED never moves at all.
contract WarHandler is Test {
    Villages public game;
    Army public army;
    SeedLedger public ledger;
    Clans public clans;
    MockCore public core;
    address[3] public players;
    uint256 public clanId;

    bool public conservationBroken;
    bool public raidLimitBroken;
    string public brokenReason;
    uint256 public decisiveVillageRaids;
    uint256 public lootTaken;
    uint256 public lootReturned;
    uint256 public battles;
    mapping(bytes32 => uint256) public arrivals;

    constructor(
        Villages game_,
        Army army_,
        SeedLedger ledger_,
        Clans clans_,
        MockCore core_,
        address[3] memory p,
        uint256 clanId_
    ) {
        game = game_;
        army = army_;
        ledger = ledger_;
        clans = clans_;
        core = core_;
        players = p;
        clanId = clanId_;
    }

    struct Snap {
        uint256[4][3] stock;
        uint256[3] seed;
    }

    function _snap() internal view returns (Snap memory s) {
        for (uint256 i; i < 3; ++i) {
            s.stock[i] = game.stock(players[i]);
            s.seed[i] = game.seedBalance(players[i]);
        }
    }

    function _fail(string memory why) internal {
        if (!conservationBroken) brokenReason = why;
        conservationBroken = true;
    }

    function _sameStock(Snap memory a, Snap memory b, uint256 i) internal pure returns (bool) {
        return keccak256(abi.encode(a.stock[i])) == keccak256(abi.encode(b.stock[i]));
    }

    /// @dev Nobody's resources or SEED may change, except the actor's when the action spends its own.
    function _check(Snap memory s0, uint256 actor, bool actorStock, bool actorSeed) internal {
        Snap memory s1 = _snap();
        for (uint256 i; i < 3; ++i) {
            bool isActor = i == actor;
            if (!_sameStock(s0, s1, i) && !(isActor && actorStock)) _fail("stock of a bystander changed");
            if (s0.seed[i] != s1.seed[i] && !(isActor && actorSeed)) _fail("SEED of a bystander changed");
            if (isActor && actorStock) {
                for (uint256 r; r < 4; ++r) {
                    if (s1.stock[i][r] > s0.stock[i][r]) _fail("own action created resources");
                }
            }
        }
    }

    function _idx(address who) internal view returns (uint256) {
        for (uint256 i; i < 3; ++i) {
            if (players[i] == who) return i;
        }
        return 3;
    }

    function advance(uint32 elapsed, uint32 work) external {
        Snap memory s0 = _snap();
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1 hours, 1 days));
        core.setWork(core.work() + uint64(bound(work, 0, 40_000)));
        try ledger.checkpoint() {} catch {}
        Snap memory s1 = _snap();
        for (uint256 i; i < 3; ++i) {
            if (s0.seed[i] != s1.seed[i]) _fail("checkpoint moved SEED");
        }
    }

    function claim(uint8 a) external {
        a %= 3;
        Snap memory s0 = _snap();
        vm.prank(players[a]);
        try game.claimSeed() {} catch {}
        _check(s0, a, false, true);
        if (game.seedBalance(players[a]) < s0.seed[a]) _fail("claim reduced SEED");
    }

    function train(uint8 a, uint8 kind, uint8 count) external {
        a %= 3;
        Snap memory s0 = _snap();
        vm.prank(players[a]);
        try game.train([uint8(0), 2, 6][kind % 3], uint32(bound(count, 1, 12))) {} catch {}
        _check(s0, a, true, false);
    }

    function completeTraining(uint8 a) external {
        Snap memory s0 = _snap();
        try army.completeTraining(address(game), players[a % 3]) {} catch {}
        _check(s0, 3, false, false);
    }

    function _move(uint8 a, uint8 t, uint8 kind, uint256 count, bool champion, uint8 mode, uint16 camp)
        internal
    {
        a %= 3;
        address who = players[a];
        address target = camp != type(uint16).max ? address(0) : players[(a + 1 + t % 2) % 3];
        uint32 home = army.home(address(game), who)[kind];
        if (home == 0) return;
        uint32[7] memory units;
        units[kind] = uint32(bound(count, (uint256(home) + 1) / 2, home));
        Snap memory s0 = _snap();
        vm.prank(who);
        try game.send(target, camp == type(uint16).max ? 0 : camp, units, champion, mode) returns (uint256) {}
            catch {}
        _check(s0, 3, false, false);
    }

    function raid(uint8 a, uint8 t, uint256 count, bool champion) external {
        _move(a, t, 0, count, champion, 1, type(uint16).max);
    }

    function scout(uint8 a, uint8 t, uint256 count) external {
        _move(a, t, 6, count, false, 2, type(uint16).max);
    }

    function support(uint8 a, uint8 t, uint256 count) external {
        _move(a, t, 0, count, false, 3, type(uint16).max);
    }

    function raidCamp(uint8 a, uint8 camp, uint256 count, bool champion) external {
        _move(a, 0, 0, count, champion, 1, uint16(camp % 200));
    }

    function resolve(uint256 id) external {
        uint256 count = army.movementCount(address(game));
        if (count == 0) return;
        // Start at a random movement and take the first one that has arrived, so return legs
        // (and the loot they carry home) are reached as often as outbound legs.
        uint256 start = bound(id, 1, count);
        Army.Movement memory m0;
        for (uint256 k; k < count; ++k) {
            id = (start - 1 + k) % count + 1;
            m0 = army.movement(address(game), id);
            if (m0.mode >= 1 && m0.mode <= 4 && m0.arriveAt <= vm.getBlockTimestamp()) break;
        }
        Snap memory s0 = _snap();
        try army.resolve(address(game), id) {}
        catch {
            return;
        }
        Army.Movement memory m1 = army.movement(address(game), id);
        Snap memory s1 = _snap();
        uint256 touched = 3;
        if (m0.mode == 1) {
            Army.Report memory r = army.report(address(game), id);
            if (!r.cancelled) {
                ++battles;
                bytes32 key = keccak256(
                    abi.encode(
                        m0.owner, m0.target, m0.target == address(0) ? m0.campId : 0, ledger.currentDay()
                    )
                );
                if (++arrivals[key] > 3) raidLimitBroken = true;
            }
            if (m0.target != address(0)) {
                touched = _idx(m0.target);
                uint256 taken;
                for (uint256 r_; r_ < 4; ++r_) {
                    if (s0.stock[touched][r_] < s1.stock[touched][r_]) {
                        _fail("battle credited the defender");
                    } else if (s0.stock[touched][r_] - s1.stock[touched][r_] != m1.loot[r_]) {
                        _fail("defender lost other than the carried loot");
                    }
                    if (s1.stock[touched][r_] < game.vaultProtection(m0.target) && m1.loot[r_] != 0) {
                        _fail("loot dug into the Vault");
                    }
                    taken += m1.loot[r_];
                }
                lootTaken += taken;
                if (r.decisive && !r.cancelled) ++decisiveVillageRaids;
                if (!r.decisive && taken != 0) _fail("indecisive battle took loot");
            }
        } else if (m0.mode == 4) {
            touched = _idx(m0.owner);
            uint256 cap = game.storageCapacity(m0.owner);
            for (uint256 r_; r_ < 4; ++r_) {
                uint256 expected = G.min(cap, s0.stock[touched][r_] + m0.loot[r_]);
                if (s1.stock[touched][r_] != expected) _fail("returned loot credited incorrectly");
                lootReturned += m0.loot[r_];
            }
        }
        for (uint256 i; i < 3; ++i) {
            if (s0.seed[i] != s1.seed[i]) _fail("movement moved SEED");
            if (i != touched && !_sameStock(s0, s1, i)) _fail("movement touched an uninvolved village");
        }
    }

    function recall(uint8 a, uint256 id) external {
        uint256 count = army.movementCount(address(game));
        if (count == 0) return;
        Snap memory s0 = _snap();
        vm.prank(players[a % 3]);
        try game.recall(bound(id, 1, count)) {} catch {}
        _check(s0, 3, false, false);
    }

    function returnFormerSupport(uint256 id) external {
        uint256 count = army.movementCount(address(game));
        if (count == 0) return;
        Snap memory s0 = _snap();
        try army.returnFormerSupport(address(game), bound(id, 1, count)) {} catch {}
        _check(s0, 3, false, false);
    }

    /// @dev The founder (players[0]) opens or revokes an invitation; a non-founder's attempt must revert.
    function invite(uint8 a, uint8 by, bool open) external {
        address who = players[1 + a % 2];
        address inviter = players[by % 3];
        Snap memory s0 = _snap();
        vm.prank(inviter);
        try game.inviteToClan(who, open) {
            if (inviter != players[0]) _fail("non-founder invited");
            if (clans.invited(address(game), clanId, who) != open) _fail("invitation not recorded");
        } catch {
            if (inviter == players[0]) _fail("founder invite reverted");
        }
        _check(s0, 3, false, false);
    }

    function toggleClan(uint8 a) external {
        address who = players[1 + a % 2];
        Snap memory s0 = _snap();
        if (clans.clanOf(address(game), who) != 0) {
            vm.prank(who);
            try game.leaveClan() {} catch {}
        } else {
            bool wasInvited = clans.invited(address(game), clanId, who);
            vm.prank(who);
            try game.joinClan(clanId) {
                if (!wasInvited) _fail("joined without invitation");
                if (clans.invited(address(game), clanId, who)) _fail("invitation not consumed");
            } catch {}
        }
        _check(s0, 3, false, false);
    }

    function peace(uint8 a) external {
        a %= 3;
        Snap memory s0 = _snap();
        vm.prank(players[a]);
        try game.treasury(1, 0) {
            if (game.seedBalance(players[a]) + 4000 * 1e6 != s0.seed[a]) _fail("peace shield price wrong");
        } catch {}
        _check(s0, a, false, true);
    }

    function sync(uint8 a) external {
        Snap memory s0 = _snap();
        game.sync(players[a % 3]);
        _check(s0, 3, false, false);
    }
}

contract WarInvariantTest is StdInvariant, EndgameTest {
    WarHandler internal handler;
    address[3] internal people;

    function setUp() public override {
        super.setUp();
        _found(carol, "Carol");
        _advanceTo(alice, 4);
        _clanHall(alice, 3);
        _barracks(alice);
        _burrow(alice, 3);
        _advanceTo(bob, 3);
        _clanHall(bob, 1);
        _barracks(bob);
        _advanceTo(carol, 3);
        _clanHall(carol, 1);
        _barracks(carol);
        vm.prank(alice);
        uint256 id = game.foundClan("Hams");
        vm.prank(alice);
        game.inviteToClan(bob, true);
        vm.prank(bob);
        game.joinClan(id);
        _troops(alice, 0, 100);
        _troops(alice, 6, 5);
        _troops(bob, 0, 10);
        _troops(bob, 6, 3);
        _troops(carol, 0, 10);
        _troops(carol, 6, 3);
        people = [alice, bob, carol];
        uint256 latest;
        for (uint256 i; i < 3; ++i) {
            if (game.village(people[i]).shieldUntil > latest) latest = game.village(people[i]).shieldUntil;
        }
        if (vm.getBlockTimestamp() <= latest) vm.warp(latest + 1);
        handler = new WarHandler(game, army, ledger, clans, core, people, id);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 60
    function invariant_onlyLootMovesResourcesAndSeedNeverMoves() public view {
        assertFalse(handler.conservationBroken(), handler.brokenReason());
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 60
    function invariant_atMostThreeRaidArrivalsPerTargetPerDay() public view {
        assertFalse(handler.raidLimitBroken());
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 60
    function invariant_storageAndWallsBounded() public view {
        for (uint256 p; p < 3; ++p) {
            uint256[4] memory s = game.stock(people[p]);
            for (uint256 r; r < 4; ++r) {
                assertLe(s[r], game.storageCapacity(people[p]));
            }
            assertLe(game.effectiveWalls(people[p]), game.village(people[p]).buildings[G.WALLS]);
        }
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 60
    function invariant_roomChampionAndSupportAccounting() public view {
        uint256 count = army.movementCount(address(game));
        for (uint256 p; p < 3; ++p) {
            address who = people[p];
            uint256 room;
            uint32[7] memory atHome = army.home(address(game), who);
            for (uint8 i; i < 7; ++i) {
                (,,,, uint256 r,) = rules.unitStats(i);
                room += atHome[i] * r;
            }
            Army.Training memory t = army.training(address(game), who);
            if (t.readyAt != 0) {
                (,,,, uint256 r,) = rules.unitStats(t.kind);
                room += t.count * r;
            }
            bool championOut;
            uint256 stationedHere;
            for (uint256 id = 1; id <= count; ++id) {
                Army.Movement memory m = army.movement(address(game), id);
                if (m.owner == who && m.mode != 6) {
                    for (uint8 i; i < 7; ++i) {
                        (,,,, uint256 r,) = rules.unitStats(i);
                        room += m.units[i] * r;
                    }
                    if (m.champion) {
                        assertFalse(championOut, "champion on two movements");
                        championOut = true;
                    }
                }
                if (m.mode == 5 && m.target == who) ++stationedHere;
                if (m.mode == 6) {
                    for (uint8 i; i < 7; ++i) {
                        assertEq(m.units[i], 0, "completed movement still holds troops");
                    }
                    assertEq(
                        m.loot[0] + m.loot[1] + m.loot[2] + m.loot[3], 0, "completed movement holds loot"
                    );
                }
            }
            assertEq(army.allocatedRoom(address(game), who), room, "room drifted from troops");
            assertLe(room, game.roomCapacity(who));
            assertEq(army.champion(address(game), who).away, championOut, "champion flag drifted");
            uint256[] memory list = army.supportMovements(address(game), who);
            assertEq(list.length, stationedHere, "support list drifted from stationed movements");
            for (uint256 i; i < list.length; ++i) {
                Army.Movement memory s = army.movement(address(game), list[i]);
                assertEq(s.mode, 5);
                assertEq(s.target, who);
                uint256 remaining;
                for (uint256 k; k < 7; ++k) {
                    remaining += s.units[k];
                }
                assertGt(remaining, 0, "empty support retains a slot");
                for (uint256 j; j < i; ++j) {
                    assertTrue(list[i] != list[j], "duplicate support entry");
                }
            }
        }
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 60
    function invariant_seedConservationAndClanConsistency() public view {
        uint256 total;
        for (uint256 p; p < 3; ++p) {
            total += game.seedBalance(people[p]);
        }
        assertEq(total, ledger.minted(address(game)) - ledger.burned(address(game)));
        uint256 id = handler.clanId();
        Clans.Clan memory c = clans.clan(address(game), id);
        assertLe(c.members.length, c.capacity);
        uint256 members;
        for (uint256 p; p < 3; ++p) {
            if (clans.clanOf(address(game), people[p]) == id) ++members;
        }
        assertEq(members, c.members.length);
        assertEq(clans.clanOf(address(game), alice), id, "founder left a populated clan");
        assertEq(
            address(game).balance + address(army).balance + address(ledger).balance + address(clans).balance,
            0
        );
    }
}

/// @notice Grounds the invariant harness: one scripted decisive raid passes the same per-step checks,
/// so the conservation property is not vacuous.
contract WarHarnessSanityTest is EndgameTest {
    function testScriptedDecisiveRaidMovesExactlyTheLoot() public {
        _found(carol, "Carol");
        _advanceTo(alice, 3);
        _barracks(alice);
        _burrow(alice, 3);
        _troops(alice, 0, 100);
        if (vm.getBlockTimestamp() <= game.village(carol).shieldUntil) {
            vm.warp(game.village(carol).shieldUntil + 1);
        }
        address[3] memory p = [alice, bob, carol];
        WarHandler h = new WarHandler(game, army, ledger, clans, core, p, 0);
        h.raid(0, 1, 100, true);
        assertEq(army.movementCount(address(game)), 1);
        vm.warp(army.movement(address(game), 1).arriveAt);
        h.resolve(1);
        assertEq(h.decisiveVillageRaids(), 1);
        assertGt(h.lootTaken(), 0);
        vm.warp(army.movement(address(game), 1).arriveAt);
        h.resolve(1);
        assertEq(h.lootReturned(), h.lootTaken());
        assertFalse(h.conservationBroken(), h.brokenReason());
        assertEq(army.movement(address(game), 1).mode, 6);
    }
}
