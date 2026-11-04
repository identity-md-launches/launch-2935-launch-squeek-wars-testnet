// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameErrors as E} from "../src/libraries/GameErrors.sol";
import {GameTest} from "./helpers/GameTest.sol";
import {EndgameTest} from "./helpers/EndgameTest.sol";
import {MockCore} from "./helpers/Mocks.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";
import {SeedLedger} from "../src/SeedLedger.sol";
import {Villages} from "../src/Villages.sol";
import {Army} from "../src/Army.sol";

/// @notice Independent adversarial checks of SeedLedger failure paths and the owner's only powers.
contract LedgerEdgeTest is GameTest {
    function testRegisterRejectsZeroAndDuplicateInEveryNamespace() public {
        vm.expectRevert(E.AlreadyRegisteredOrInvalidPlayer.selector);
        ledger.register(address(0));
        vm.prank(address(game));
        vm.expectRevert(E.AlreadyRegisteredOrInvalidPlayer.selector);
        ledger.register(alice);
        // A foreign namespace may register the same wallet, but it never touches the canonical account.
        vm.prank(outsider);
        ledger.register(alice);
        assertEq(ledger.balanceOf(outsider, alice), 1500 * U);
        assertEq(game.seedBalance(alice), 1500 * U);
        assertEq(ledger.minted(address(game)), 3000 * U);
    }

    function testBurnAndRefundAreBoundedPerNamespace() public {
        vm.startPrank(outsider);
        ledger.register(outsider);
        vm.expectRevert(SeedLedger.InsufficientSeed.selector);
        ledger.burn(outsider, 1500 * U + 1);
        ledger.burn(outsider, 1500 * U);
        assertEq(ledger.balanceOf(outsider, outsider), 0);
        vm.expectRevert(E.InvalidRefund.selector);
        ledger.refund(outsider, 1500 * U + 1);
        ledger.refund(outsider, 1500 * U);
        // Canonical players are not accounts of the outsider's namespace.
        vm.expectRevert(SeedLedger.InsufficientSeed.selector);
        ledger.burn(alice, 0);
        vm.expectRevert(E.InvalidRefund.selector);
        ledger.refund(alice, 0);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        ledger.claim(alice);
        vm.stopPrank();
        assertEq(game.seedBalance(alice), 1500 * U);
        assertEq(ledger.burned(address(game)), 0);
        // Even the canonical namespace cannot refund more than it ever burned.
        vm.prank(address(game));
        vm.expectRevert(E.InvalidRefund.selector);
        ledger.refund(alice, 1);
    }

    function testOwnerPowersAreOnlyTheTimelockedRepoint() public {
        MockCore other = new MockCore();
        address[4] memory callers = [outsider, alice, address(game), address(army)];
        for (uint256 i; i < callers.length; ++i) {
            vm.startPrank(callers[i]);
            vm.expectRevert(SeedLedger.Unauthorized.selector);
            ledger.proposeRepoint(address(other), address(nft));
            vm.expectRevert(SeedLedger.Unauthorized.selector);
            ledger.applyRepoint();
            vm.expectRevert(SeedLedger.Unauthorized.selector);
            ledger.cancelRepoint();
            vm.expectRevert(SeedLedger.Unauthorized.selector);
            ledger.renounceOwnership();
            vm.stopPrank();
        }
        vm.startPrank(owner);
        vm.expectRevert(SeedLedger.InvalidAddress.selector);
        ledger.proposeRepoint(address(0), address(nft));
        vm.expectRevert(SeedLedger.InvalidAddress.selector);
        ledger.proposeRepoint(address(other), address(0));
        vm.expectRevert(SeedLedger.TimelockPending.selector);
        ledger.applyRepoint();
        vm.stopPrank();
    }

    function testRepointToJumpingCoreMintsNothingForTheJumpAndHonorsExactDelay() public {
        MockCore jump = new MockCore();
        jump.setWork(1e15);
        vm.prank(owner);
        ledger.proposeRepoint(address(jump), address(nft));
        uint256 at = ledger.repointAfter();
        assertEq(at, block.timestamp + 72 hours);
        vm.warp(at - 1);
        vm.prank(owner);
        vm.expectRevert(SeedLedger.TimelockPending.selector);
        ledger.applyRepoint();
        vm.warp(at);
        vm.prank(owner);
        ledger.applyRepoint();
        assertEq(ledger.core(), address(jump));
        assertEq(ledger.lastCumulativeWork(), 1e15);
        assertEq(ledger.pendingCore(), address(0));
        assertEq(ledger.repointAfter(), 0);
        vm.warp((ledger.currentDay() + 1) * 1 days + 4 hours);
        jump.setWork(1e15 + 5000);
        ledger.checkpoint();
        assertEq(ledger.observation(ledger.observationCount() - 1).work, 5000);
        vm.prank(alice);
        (uint256 seed, uint256 xp) = game.claimSeed();
        assertEq(seed, 500 * U);
        assertEq(xp, 50);
        // An applied repoint cannot be applied a second time without a new proposal.
        vm.prank(owner);
        vm.expectRevert(SeedLedger.TimelockPending.selector);
        ledger.applyRepoint();
    }

    function testRepointToBrokenCoreOrNFTRevertsAndKeepsCurrentSources() public {
        MockCore broken = new MockCore();
        broken.setBroken(true);
        vm.prank(owner);
        ledger.proposeRepoint(address(broken), address(nft));
        vm.warp(vm.getBlockTimestamp() + 72 hours);
        vm.prank(owner);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.applyRepoint();
        assertEq(ledger.core(), address(core));
        assertEq(ledger.pendingCore(), address(broken));
        // A pending NFT without code fails the balanceOf probe.
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(0xC0DE));
        vm.warp(vm.getBlockTimestamp() + 72 hours);
        vm.prank(owner);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.applyRepoint();
        assertEq(ledger.squeek(), address(nft));
    }

    function testRenouncedOwnerHasNoPowerLeft() public {
        vm.prank(owner);
        ledger.proposeRepoint(address(core), address(nft));
        vm.prank(owner);
        ledger.renounceOwnership();
        assertEq(ledger.owner(), address(0));
        assertEq(ledger.repointAfter(), 0);
        vm.warp(vm.getBlockTimestamp() + 72 hours);
        vm.startPrank(owner);
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.applyRepoint();
        vm.expectRevert(SeedLedger.Unauthorized.selector);
        ledger.proposeRepoint(address(core), address(nft));
        vm.stopPrank();
        vm.prank(address(0));
        vm.expectRevert(SeedLedger.TimelockPending.selector);
        ledger.applyRepoint();
    }

    function testCheckpointOncePerDayAtExactBoundary() public {
        uint256 boundary = (ledger.currentDay() + 1) * 1 days + 4 hours;
        vm.warp(boundary - 1);
        vm.expectRevert(SeedLedger.AlreadyCheckpointed.selector);
        ledger.checkpoint();
        vm.warp(boundary);
        ledger.checkpoint();
        vm.expectRevert(SeedLedger.AlreadyCheckpointed.selector);
        ledger.checkpoint();
        vm.warp(boundary + 1 days - 1);
        vm.expectRevert(SeedLedger.AlreadyCheckpointed.selector);
        ledger.checkpoint();
        vm.prank(alice);
        game.claimSeed();
        vm.prank(alice);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        game.claimSeed();
    }

    function testWheelIntegralRejectsInvalidQueries() public {
        vm.expectRevert(E.InvalidIntegralQuery.selector);
        ledger.wheelIntegral(11, block.timestamp);
        vm.expectRevert(E.InvalidIntegralQuery.selector);
        ledger.wheelIntegral(1, block.timestamp + 1);
        assertEq(ledger.wheelIntegral(0, block.timestamp), 0);
        assertEq(ledger.wheelIntegral(5, 0), 0);
    }

    function testUnfoundedWalletCannotClaimSeed() public {
        vm.prank(outsider);
        vm.expectRevert(Villages.NoVillage.selector);
        game.claimSeed();
    }
}

/// @notice Village failure paths: every rejected order leaves the village exactly as it was.
contract VillageEdgeTest is EndgameTest {
    function testNameBoundariesAndCharacters() public {
        address d = address(0xD00D);
        string[6] memory bad = ["ab", "abcdefghijklmnopq", "", "a-b", "ab c", unicode"äbc"];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(d);
            vm.expectRevert();
            game.found(bad[i]);
        }
        vm.prank(d);
        vm.expectRevert(E.InvalidNameCharacter.selector);
        game.found("a-b");
        vm.prank(d);
        vm.expectRevert(E.InvalidNameLength.selector);
        game.found("ab");
        vm.prank(d);
        vm.expectRevert(E.NameTaken.selector);
        game.found("aLiCe");
        _found(carol, "c_9");
        _found(d, "ABCDEFGHIJKLMNOP");
        assertEq(game.villageCount(), 4);
        vm.prank(alice);
        vm.expectRevert(Villages.InvalidAction.selector);
        game.found("AliceTwo");
    }

    function testBuildOrderRejections() public {
        vm.startPrank(alice);
        vm.expectRevert(E.InvalidBuildSlot.selector);
        game.orderBuild(19, 0);
        vm.expectRevert(E.InvalidBuildSlot.selector);
        game.orderBuild(0, 2);
        vm.expectRevert(E.FieldCappedByTownHall.selector);
        game.orderBuild(0, 0);
        vm.expectRevert(E.BuildingCappedByTownHall.selector);
        game.orderBuild(8 + G.WALLS, 0);
        vm.expectRevert(E.ResearchVaultFirst.selector);
        game.orderBuild(8 + G.VAULT, 0);
        vm.expectRevert(E.ResearchTier2First.selector);
        game.orderBuild(8 + G.FORGE, 0);
        vm.expectRevert(E.ResearchTier2First.selector);
        game.orderBuild(8 + G.CLAN, 0);
        game.orderBuild(8 + G.TH, 0);
        vm.expectRevert(E.AlreadyBuildingTarget.selector);
        game.orderBuild(8 + G.TH, 1);
        vm.expectRevert(E.InvalidBuildSlot.selector);
        game.orderBuild(8 + G.BARRACKS, 0);
        game.orderBuild(8 + G.BARRACKS, 1);
        vm.expectRevert(E.InvalidBuildSlot.selector);
        game.orderBuild(8 + G.MARKET, 1);
        vm.stopPrank();
    }

    function testCompleteAndCancelTiming() public {
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 0);
        Villages.BuildOrder memory b = game.buildOrder(alice, 0);
        vm.warp(b.readyAt - 1);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeBuild(alice, 0);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeBuild(alice, 1);
        vm.expectRevert(E.InvalidSlot.selector);
        game.completeBuild(alice, 2);
        // Another wallet cannot cancel it: cancel only ever looks at the caller's own slots.
        vm.prank(bob);
        vm.expectRevert(E.CannotCancelCompletedBuild.selector);
        game.cancelBuild(0);
        assertEq(game.buildOrder(alice, 0).readyAt, b.readyAt);
        vm.warp(b.readyAt);
        vm.prank(alice);
        vm.expectRevert(E.CannotCancelCompletedBuild.selector);
        game.cancelBuild(0);
        vm.prank(outsider);
        game.completeBuild(alice, 0);
        assertEq(game.village(alice).buildings[G.TH], 2);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeBuild(alice, 0);
        vm.prank(alice);
        vm.expectRevert(E.CannotCancelCompletedBuild.selector);
        game.cancelBuild(0);
    }

    function testCancelRefundsEightyPercentOfSeedToo() public {
        _fill(alice);
        _fundedBuild(alice, 8 + G.STORE);
        _fill(alice);
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 0);
        Villages.BuildOrder memory b = game.buildOrder(alice, 0);
        assertEq(b.seed, 667 * U * 15 / 10);
        uint256 seedAfterOrder = game.seedBalance(alice);
        vm.prank(alice);
        game.cancelBuild(0);
        assertEq(game.seedBalance(alice), seedAfterOrder + b.seed * 80 / 100);
        assertEq(ledger.burned(address(game)), b.seed - b.seed * 80 / 100);
        vm.prank(alice);
        vm.expectRevert(E.CannotCancelCompletedBuild.selector);
        game.cancelBuild(0);
    }

    function testResearchRejections() public {
        vm.prank(alice);
        vm.expectRevert(E.AcademyTooLow.selector);
        game.orderResearch();
        _build(alice, 8 + G.ACADEMY);
        vm.prank(alice);
        game.orderResearch();
        vm.prank(alice);
        vm.expectRevert(E.ResearchBusy.selector);
        game.orderResearch();
        Villages.Study memory s = game.study(alice);
        vm.warp(s.readyAt - 1);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeResearch(alice);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeResearch(bob);
        vm.warp(s.readyAt);
        game.completeResearch(alice);
        assertEq(game.village(alice).tier, 1);
        vm.expectRevert(Villages.NotReady.selector);
        game.completeResearch(alice);
        // Tier 2 needs Academy 2, which Town Hall 1 cannot host.
        vm.prank(alice);
        vm.expectRevert(E.AcademyTooLow.selector);
        game.orderResearch();
    }

    function testExchangeRejectionsAreAtomic() public {
        vm.prank(alice);
        vm.expectRevert(E.MarketRequired.selector);
        game.exchange(0, 1, 1);
        _build(alice, 8 + G.MARKET);
        uint8[5] memory ins = [0, 5, 0, 0, 0];
        uint8[5] memory outs = [0, 0, 4, 1, 1];
        uint256[5] memory lots = [uint256(1), 1, 1, 0, 1_000_001];
        for (uint256 i; i < 5; ++i) {
            vm.prank(alice);
            vm.expectRevert(E.InvalidExchange.selector);
            game.exchange(ins[i], outs[i], lots[i]);
        }
        uint256[4] memory before_ = game.stock(alice);
        uint256 seedBefore = game.seedBalance(alice);
        vm.prank(alice);
        vm.expectRevert(Villages.InsufficientResources.selector);
        game.exchange(0, 1, before_[0] / (100 * U) + 1);
        vm.prank(alice);
        vm.expectRevert(SeedLedger.InsufficientSeed.selector);
        game.exchange(4, 1, 16);
        assertEq(keccak256(abi.encode(game.stock(alice))), keccak256(abi.encode(before_)));
        assertEq(game.seedBalance(alice), seedBefore);
        _fill(alice);
        uint256[4] memory full = game.stock(alice);
        vm.prank(alice);
        vm.expectRevert(E.InsufficientStorage.selector);
        game.exchange(0, 1, 1);
        vm.prank(alice);
        vm.expectRevert(E.InsufficientStorage.selector);
        game.exchange(4, 1, 1);
        assertEq(keccak256(abi.encode(game.stock(alice))), keccak256(abi.encode(full)));
        assertEq(game.seedBalance(alice), seedBefore);
    }

    function testTreasuryRejectionsAndExactSeedBurns() public {
        vm.startPrank(alice);
        vm.expectRevert(Villages.InvalidAction.selector);
        game.treasury(3, 0);
        vm.expectRevert(E.BoostActiveOrInvalidResource.selector);
        game.treasury(0, 4);
        uint64 shield = game.village(alice).shieldUntil;
        // The 7-day founding shield outlasts a 12 h peace shield: buying one now would burn 4,000 SEED
        // for nothing, so it is refused before any SEED is checked.
        vm.expectRevert(E.ShieldAlreadyActive.selector);
        game.treasury(1, 0);
        vm.warp(shield);
        vm.expectRevert(SeedLedger.InsufficientSeed.selector);
        game.treasury(1, 0);
        assertEq(game.village(alice).peaceUsedAt, 0);
        assertEq(game.village(alice).shieldUntil, shield);
        game.treasury(2, 0);
        assertEq(game.seedBalance(alice), 500 * U);
        vm.expectRevert(E.BannerAlreadyOwned.selector);
        game.treasury(2, 0);
        game.treasury(0, 3);
        assertEq(game.seedBalance(alice), 0);
        vm.expectRevert(E.BoostActiveOrInvalidResource.selector);
        game.treasury(0, 2);
        vm.stopPrank();
        assertEq(ledger.burned(address(game)), 1500 * U);
        assertEq(game.seedBalance(bob), 1500 * U);
    }

    function testClanActionsRejectedWithoutClanHallOrMembership() public {
        vm.startPrank(alice);
        vm.expectRevert(E.ClanHall3Required.selector);
        game.foundClan("Hams");
        vm.expectRevert(E.CannotJoin.selector);
        game.joinClan(1);
        vm.expectRevert(E.NotInClan.selector);
        game.leaveClan();
        vm.expectRevert(E.CannotRaiseCapacity.selector);
        game.raiseClanCapacity();
        vm.stopPrank();
        vm.prank(outsider);
        vm.expectRevert(Villages.NoVillage.selector);
        game.foundClan("Hams");
    }

    function testJoinMissingOrFullClan() public {
        _advanceTo(alice, 3);
        _clanHall(alice, 3);
        _advanceTo(bob, 2);
        _clanHall(bob, 1);
        vm.prank(bob);
        vm.expectRevert(E.ClanFullOrMissing.selector);
        game.joinClan(1);
        vm.prank(alice);
        uint256 id = game.foundClan("Hams");
        vm.prank(alice);
        vm.expectRevert(E.AlreadyInClan.selector);
        game.foundClan("Other");
        vm.prank(alice);
        vm.expectRevert(E.CannotRaiseCapacity.selector);
        game.raiseClanCapacity();
        vm.prank(bob);
        vm.expectRevert(E.ClanFullOrMissing.selector);
        game.joinClan(id + 1);
        vm.prank(bob);
        vm.expectRevert(E.NotInvited.selector);
        game.joinClan(id);
        // Only the founder invites; a revoked invitation admits nobody.
        vm.prank(bob);
        vm.expectRevert(E.OnlyFounderInvites.selector);
        game.inviteToClan(bob, true);
        vm.prank(alice);
        vm.expectRevert(E.OnlyFounderInvites.selector);
        game.inviteToClan(address(0), true);
        vm.startPrank(alice);
        game.inviteToClan(bob, true);
        game.inviteToClan(bob, false);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(E.NotInvited.selector);
        game.joinClan(id);
        vm.prank(alice);
        game.inviteToClan(bob, true);
        vm.prank(bob);
        game.joinClan(id);
        assertFalse(clans.invited(address(game), id, bob), "invitation not consumed");
        vm.prank(bob);
        vm.expectRevert(E.CannotJoin.selector);
        game.joinClan(id);
        vm.prank(bob);
        vm.expectRevert(E.CannotRaiseCapacity.selector);
        game.raiseClanCapacity();
        assertEq(clans.clan(address(game), id).members.length, 2);
        // Leaving does not leave a standing invitation behind: rejoining needs a fresh one.
        vm.prank(bob);
        game.leaveClan();
        vm.prank(bob);
        vm.expectRevert(E.NotInvited.selector);
        game.joinClan(id);
    }

    function testPeaceShieldExtendsOnlyAnExpiredOrShorterShieldAndRespectsCooldown() public {
        // Fund alice above two shields' worth through a real checkpoint and claim.
        vm.warp(game.village(alice).shieldUntil);
        _checkpoint(1_000_000_000);
        vm.prank(alice);
        game.claimSeed();
        uint256 before = game.seedBalance(alice);
        assertGe(before, 8000 * U);
        uint256 burnedBefore = ledger.burned(address(game));
        vm.prank(alice);
        game.treasury(1, 0);
        assertEq(game.seedBalance(alice), before - 4000 * U);
        assertEq(game.village(alice).shieldUntil, vm.getBlockTimestamp() + 12 hours);
        assertEq(game.village(alice).peaceUsedAt, vm.getBlockTimestamp());
        // A second purchase while this shield runs is refused before the cooldown or any burn.
        vm.prank(alice);
        vm.expectRevert(E.PeaceCooldown.selector);
        game.treasury(1, 0);
        // Cooldown is exactly 3 days from purchase.
        uint256 bought = vm.getBlockTimestamp();
        vm.warp(bought + 3 days - 1);
        vm.prank(alice);
        vm.expectRevert(E.PeaceCooldown.selector);
        game.treasury(1, 0);
        vm.warp(bought + 3 days);
        vm.prank(alice);
        game.treasury(1, 0);
        assertEq(game.seedBalance(alice), before - 8000 * U);
        assertEq(ledger.burned(address(game)) - burnedBefore, 8000 * U);
        assertEq(game.village(alice).shieldUntil, bought + 3 days + 12 hours);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzNameUniquenessIgnoresCase(uint16 mask) public {
        bytes memory name = bytes("Hamster_42");
        for (uint256 i; i < name.length; ++i) {
            uint8 c = uint8(name[i]);
            if ((mask >> i) & 1 == 1) {
                if (c >= 97 && c <= 122) name[i] = bytes1(c - 32);
                else if (c >= 65 && c <= 90) name[i] = bytes1(c + 32);
            }
        }
        _found(carol, "hamster_42");
        vm.prank(address(0xD00D));
        vm.expectRevert(E.NameTaken.selector);
        game.found(string(name));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzExchangeExactArithmetic(uint8 input, uint8 output, uint256 lots) public {
        _build(alice, 8 + G.MARKET);
        input %= 5;
        output %= 4;
        if (input == output) output = (output + 1) % 4;
        uint256[4] memory before_ = game.stock(alice);
        uint256 seedBefore = game.seedBalance(alice);
        uint256 maxLots = input == 4 ? seedBefore / (100 * U) : before_[input] / (100 * U);
        lots = bound(lots, 1, maxLots);
        vm.prank(alice);
        game.exchange(input, output, lots);
        uint256[4] memory after_ = game.stock(alice);
        for (uint8 i; i < 4; ++i) {
            uint256 expected = before_[i];
            if (i == input) expected -= lots * 100 * U;
            if (i == output) expected += lots * 25 * U;
            assertEq(after_[i], expected);
        }
        assertEq(game.seedBalance(alice), input == 4 ? seedBefore - lots * 100 * U : seedBefore);
        assertEq(game.seedBalance(bob), 1500 * U);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzSqueekSpeedMonotoneAndNeverBeyondThirtyPercent(
        uint32 base,
        uint8 th,
        uint256 n1,
        uint256 n2,
        uint64 w1,
        uint64 w2
    ) public view {
        th = uint8(bound(th, 1, 10));
        n1 = bound(n1, 0, 1000);
        n2 = bound(n2, n1, 1000);
        if (w2 < w1) (w1, w2) = (w2, w1);
        uint256 plain = rules.buildDuration(base, th, 0, w2);
        uint256 a = rules.buildDuration(base, th, n1, w1);
        uint256 b = rules.buildDuration(base, th, n2, w2);
        assertEq(plain, rules.buildDuration(base, th, 5, 0), "no work, no Squeek bonus");
        assertLe(a, plain);
        assertLe(b, a, "more Squeeks or more work never slows a build");
        assertGe(b * 10 + 10, plain * 7, "Squeek bonus never beyond 30%");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzTravelSymmetricAndSlowerIsNeverFaster(uint16 from, uint16 to, uint256 s1, uint256 s2)
        public
        view
    {
        from %= 10000;
        to %= 10000;
        s1 = bound(s1, 1, 100);
        s2 = bound(s2, s1, 100);
        uint256 slow = army.travelTime(from, to, s1);
        assertEq(slow, army.travelTime(to, from, s1));
        assertGe(slow, army.travelTime(from, to, s2));
        assertGt(army.travelTime(from, to, s2), 0);
    }
}

/// @notice Army failure paths through the canonical player entry point.
contract ArmyEdgeTest is EndgameTest {
    function setUp() public override {
        super.setUp();
        _barracks(alice);
        _troops(alice, 0, 10);
    }

    function _units(uint8 kind, uint32 count) internal pure returns (uint32[7] memory units) {
        units[kind] = count;
    }

    function testSendRejections() public {
        vm.startPrank(alice);
        vm.expectRevert(E.InvalidMovement.selector);
        game.send(bob, 0, _units(0, 1), false, 0);
        vm.expectRevert(E.InvalidMovement.selector);
        game.send(bob, 0, _units(0, 1), false, 4);
        vm.expectRevert(E.InvalidMovement.selector);
        game.send(alice, 0, _units(0, 1), false, 1);
        vm.expectRevert(E.MissingTarget.selector);
        game.send(outsider, 0, _units(0, 1), false, 1);
        vm.expectRevert(E.TargetProtected.selector);
        game.send(bob, 0, _units(0, 1), false, 1);
        vm.expectRevert(E.InvalidCampMovement.selector);
        game.send(address(0), 200, _units(0, 1), false, 1);
        vm.expectRevert(E.InvalidCampMovement.selector);
        game.send(address(0), 0, _units(6, 1), false, 2);
        vm.expectRevert(E.InvalidCampMovement.selector);
        game.send(address(0), 0, _units(0, 1), false, 3);
        vm.expectRevert(E.InvalidTroopCount.selector);
        game.send(address(0), 0, _units(0, 0), false, 1);
        vm.expectRevert(E.InsufficientTroops.selector);
        game.send(address(0), 0, _units(0, 11), false, 1);
        vm.stopPrank();
        vm.warp(game.village(bob).shieldUntil);
        vm.startPrank(alice);
        vm.expectRevert(E.OnlyScoutsReconnoitre.selector);
        game.send(bob, 0, _units(0, 1), false, 2);
        vm.expectRevert(E.InsufficientTroops.selector);
        game.send(bob, 0, _units(6, 1), false, 2);
        vm.expectRevert(E.InvalidSupport.selector);
        game.send(bob, 0, _units(0, 1), false, 3);
        game.send(address(0), 1, _units(0, 1), true, 1);
        vm.expectRevert(E.ChampionAway.selector);
        game.send(address(0), 2, _units(0, 1), true, 1);
        vm.stopPrank();
        assertEq(army.home(address(game), alice)[0], 9);
        assertEq(army.movementCount(address(game)), 1);
        // A wallet without a village cannot move anything.
        vm.prank(outsider);
        vm.expectRevert(Villages.NoVillage.selector);
        game.send(address(0), 0, _units(0, 1), false, 1);
    }

    function testResolveTimingAndFinality() public {
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), 999);
        uint256 id = _send(alice, address(0), 3, 0, 10, true, 1);
        Army.Movement memory m = army.movement(address(game), id);
        vm.warp(m.arriveAt - 1);
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), id);
        // Another namespace has no such movement.
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(this), id);
        vm.warp(m.arriveAt);
        army.resolve(address(game), id);
        m = army.movement(address(game), id);
        assertEq(m.mode, 4);
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), id);
        vm.prank(alice);
        vm.expectRevert(E.CannotRecallSupport.selector);
        game.recall(id);
        vm.warp(m.arriveAt);
        army.resolve(address(game), id);
        assertEq(army.movement(address(game), id).mode, 6);
        assertFalse(army.champion(address(game), alice).away);
        vm.expectRevert(E.MovementNotArrived.selector);
        army.resolve(address(game), id);
        vm.expectRevert(E.SupportStillAllied.selector);
        army.returnFormerSupport(address(game), id);
    }

    function testTrainRejections() public {
        vm.startPrank(alice);
        vm.expectRevert(E.InvalidTraining.selector);
        game.train(7, 1);
        vm.expectRevert(E.InvalidTraining.selector);
        game.train(0, 0);
        vm.expectRevert(E.InvalidTraining.selector);
        game.train(0, 1_000_001);
        vm.expectRevert(E.ResearchRequired.selector);
        game.train(1, 1);
        vm.expectRevert(E.ResearchRequired.selector);
        game.train(6, 1);
        vm.expectRevert(E.InsufficientBurrowRoom.selector);
        game.train(0, 21);
        vm.stopPrank();
        vm.expectRevert(E.TrainingNotReady.selector);
        army.completeTraining(address(game), alice);
        _fill(alice);
        vm.prank(alice);
        game.train(0, 2);
        vm.prank(alice);
        vm.expectRevert(E.TrainingBusyOrMissingVillage.selector);
        game.train(0, 1);
        Army.Training memory t = army.training(address(game), alice);
        vm.warp(t.readyAt - 1);
        vm.expectRevert(E.TrainingNotReady.selector);
        army.completeTraining(address(game), alice);
        vm.warp(t.readyAt);
        army.completeTraining(address(game), alice);
        assertEq(army.home(address(game), alice)[0], 12);
        vm.expectRevert(E.TrainingNotReady.selector);
        army.completeTraining(address(game), alice);
        // Bob has no Barracks.
        vm.prank(bob);
        vm.expectRevert(E.InvalidTraining.selector);
        game.train(0, 1);
    }

    function testInsufficientResourcesForTrainingIsAtomic() public {
        vm.prank(alice);
        game.orderBuild(8 + G.TH, 0);
        uint256[4] memory before_ = game.stock(alice);
        assertLt(before_[0], 1000 * U);
        uint256 room = army.allocatedRoom(address(game), alice);
        // 20 Spearmen cost 1,000 Wood, more than what is left after ordering Town Hall 2.
        vm.prank(alice);
        vm.expectRevert(Villages.InsufficientResources.selector);
        game.train(0, 20);
        assertEq(army.allocatedRoom(address(game), alice), room);
        assertEq(army.training(address(game), alice).readyAt, 0);
        assertEq(keccak256(abi.encode(game.stock(alice))), keccak256(abi.encode(before_)));
    }

    function testChampionAllocationRejections() public {
        vm.startPrank(alice);
        vm.expectRevert(E.InsufficientChampionPoints.selector);
        game.allocateChampion(1, 0, 0, 0);
        vm.expectRevert(E.StatCap.selector);
        game.allocateChampion(0, 21, 0, 0);
        vm.stopPrank();
        _checkpoint(20_000);
        vm.prank(alice);
        game.claimSeed();
        assertEq(army.championLevel(address(game), alice), 2);
        vm.startPrank(alice);
        game.allocateChampion(3, 1, 0, 0);
        vm.expectRevert(E.PointsCannotBeReassigned.selector);
        game.allocateChampion(4, 0, 0, 0);
        vm.expectRevert(E.InsufficientChampionPoints.selector);
        game.allocateChampion(3, 1, 1, 0);
        game.allocateChampion(3, 1, 0, 0);
        vm.stopPrank();
        (uint256 might, uint256 atk,,) = army.championStats(address(game), alice);
        assertEq(might, 50 + 3 * 25);
        assertEq(atk, 5000);
    }
}

/// @notice Two Catapult waves landing together: damage stacks and repairs one level per 12 h.
contract WallsRepairEdgeTest is EndgameTest {
    function testStackedWallDamageRepairsOneLevelPerTwelveHours() public {
        _advanceTo(alice, 10);
        _research(alice, 4);
        _barracks(alice);
        _burrow(alice, 10);
        _troops(alice, 5, 100);
        _troops(alice, 0, 100);
        _advanceTo(bob, 4);
        for (uint8 i = 1; i < 4; ++i) {
            _fundedBuild(bob, 8 + G.WALLS);
        }
        if (vm.getBlockTimestamp() <= game.village(bob).shieldUntil) {
            vm.warp(game.village(bob).shieldUntil + 1);
        }
        uint32[7] memory units;
        units[0] = 50;
        // 50 Catapults: a few fall in battle, at least 40 survive to knock down 2 levels each wave.
        units[5] = 50;
        vm.startPrank(alice);
        uint256 first = game.send(bob, 0, units, false, 1);
        uint256 second = game.send(bob, 0, units, false, 1);
        vm.stopPrank();
        uint256 arrive = army.movement(address(game), first).arriveAt;
        assertEq(arrive, army.movement(address(game), second).arriveAt);
        vm.warp(arrive);
        army.resolve(address(game), first);
        assertEq(game.effectiveWalls(bob), 2);
        army.resolve(address(game), second);
        assertTrue(army.report(address(game), second).decisive);
        assertEq(game.effectiveWalls(bob), 0);
        assertEq(game.village(bob).buildings[G.WALLS], 4);
        for (uint256 k = 1; k <= 4; ++k) {
            vm.warp(arrive + k * 12 hours - 1);
            assertEq(game.effectiveWalls(bob), k - 1);
            vm.warp(arrive + k * 12 hours);
            assertEq(game.effectiveWalls(bob), k);
        }
        vm.warp(arrive + 30 days);
        assertEq(game.effectiveWalls(bob), 4);
    }
}
