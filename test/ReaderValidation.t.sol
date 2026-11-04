// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SeedLedger} from "src/SeedLedger.sol";
import {ISqueekCore} from "src/interfaces/ISqueek.sol";

/// @dev Intentionally bypasses Solidity's return encoder so malformed external ABI data is reachable.
contract ScriptedExternalReader {
    bytes private response;
    bool private shouldRevert;
    bool private shouldWrite;
    uint256 public writes;

    function configure(bytes memory response_, bool revert_, bool write_) external {
        response = response_;
        shouldRevert = revert_;
        shouldWrite = write_;
    }

    fallback() external {
        if (shouldWrite) ++writes;
        bytes memory data = response;
        bool fail = shouldRevert;
        assembly ("memory-safe") {
            if fail { revert(add(data, 32), mload(data)) }
            return(add(data, 32), mload(data))
        }
    }
}

contract ExhaustingExternalReader {
    fallback() external {
        assembly ("memory-safe") {
            for {} 1 {} {}
        }
    }
}

contract ReaderValidationTest is Test {
    ScriptedExternalReader private core;
    ScriptedExternalReader private nft;
    SeedLedger private ledger;
    address private player;

    function setUp() public {
        vm.warp(1_800_000_000);
        player = makeAddr("reader-validation-player");
        core = new ScriptedExternalReader();
        nft = new ScriptedExternalReader();
        core.configure(_validCore(10_000), false, false);
        nft.configure(abi.encode(uint256(1)), false, false);
        ledger = new SeedLedger(address(this), address(core), address(nft));
        ledger.register(player);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function _validCore(uint64 work) private pure returns (bytes memory) {
        return abi.encode(ISqueekCore.CoreState(1, work, 2, 3, 4, 5, type(uint256).max, false));
    }

    function _stateDigest() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                ledger.observationCount(),
                ledger.observation(0),
                ledger.lastCumulativeWork(),
                ledger.account(address(this), player),
                ledger.minted(address(this)),
                ledger.burned(address(this))
            )
        );
    }

    function _rejectThenRetry() private {
        bytes32 before_ = _stateDigest();
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.checkpoint();
        assertEq(_stateDigest(), before_, "invalid external data changed checkpoint/account state");
        core.configure(_validCore(10_001), false, false);
        ledger.checkpoint();
        assertEq(ledger.observationCount(), 2, "failure must not consume today's checkpoint");
        assertEq(ledger.lastWork(), 1);
        (uint256 seed, uint256 xp) = ledger.claim(player);
        assertEq(seed, 100_000);
        assertEq(xp, 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzEachConstrainedCoreWordRejectsNoncanonicalHighBits(uint8 field, uint256 raw) public {
        uint8[7] memory fields = [uint8(0), 1, 2, 3, 4, 5, 7];
        uint256[7] memory maxima = [
            uint256(type(uint64).max),
            type(uint64).max,
            type(uint96).max,
            type(uint64).max,
            type(uint96).max,
            type(uint32).max,
            1
        ];
        uint256 selected = field % 7;
        uint256[8] memory words = abi.decode(_validCore(10_001), (uint256[8]));
        words[fields[selected]] = bound(raw, maxima[selected] + 1, type(uint256).max);
        core.configure(abi.encode(words), false, false);
        _rejectThenRetry();
    }

    function testEveryCoreWidthRejectsExactlyOneAboveMaximum() public {
        uint8[7] memory fields = [uint8(0), 1, 2, 3, 4, 5, 7];
        uint256[7] memory invalid = [
            uint256(1) << 64,
            uint256(1) << 64,
            uint256(1) << 96,
            uint256(1) << 64,
            uint256(1) << 96,
            uint256(1) << 32,
            uint256(2)
        ];
        bytes32 before_ = _stateDigest();
        for (uint256 i; i < fields.length; ++i) {
            uint256[8] memory words = abi.decode(_validCore(10_001), (uint256[8]));
            words[fields[i]] = invalid[i];
            core.configure(abi.encode(words), false, false);
            vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
            ledger.checkpoint();
            assertEq(_stateDigest(), before_);
        }
    }

    function testMaximumLegalCoreWordsAndBothBooleanEncodingsRemainAccepted() public {
        ISqueekCore.CoreState memory s = ISqueekCore.CoreState(
            type(uint64).max,
            type(uint64).max,
            type(uint96).max,
            type(uint64).max,
            type(uint96).max,
            type(uint32).max,
            type(uint256).max,
            true
        );
        core.configure(abi.encode(s), false, false);
        ledger.checkpoint();
        assertEq(ledger.lastCumulativeWork(), type(uint64).max);
        assertEq(ledger.lastWork(), uint256(type(uint64).max) - 10_000);
        s.paused = false;
        core.configure(abi.encode(s), false, false);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        ledger.checkpoint();
        assertEq(ledger.lastWork(), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzCoreRejectsEveryNonExactReplyLength(uint16 raw) public {
        uint256 length = bound(raw, 0, 511);
        if (length >= 256) ++length;
        core.configure(new bytes(length), false, false);
        _rejectThenRetry();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzNFTRejectsEveryNonExactReplyLength(uint16 raw) public {
        uint256 length = bound(raw, 0, 255);
        if (length >= 32) ++length;
        nft.configure(new bytes(length), false, false);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.nftBalance(player);
        nft.configure(abi.encode(type(uint256).max), false, false);
        assertEq(ledger.nftBalance(player), type(uint256).max);
    }

    function testInvalidCoreOnStaleRegistrationLeavesNoAccountOrGrant() public {
        address newcomer = makeAddr("reader-validation-newcomer");
        core.configure(new bytes(255), false, false);
        bytes32 before_ = _stateDigest();
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.register(newcomer);
        assertFalse(ledger.account(address(this), newcomer).exists);
        assertEq(_stateDigest(), before_);
        core.configure(_validCore(11_000), false, false);
        ledger.register(newcomer);
        assertEq(ledger.account(address(this), newcomer).cursor, 1);
        assertEq(ledger.balanceOf(address(this), newcomer), 1500 * 1_000_000);
        vm.expectRevert(SeedLedger.NoClaim.selector);
        ledger.claim(newcomer);
        (uint256 reward,) = ledger.claim(player);
        assertEq(reward, 100 * 1_000_000);
    }

    function testRevertingAndStateWritingReadersAreRejectedWithoutMutation() public {
        core.configure(_validCore(10_001), true, false);
        bytes32 before_ = _stateDigest();
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.checkpoint();
        assertEq(_stateDigest(), before_);
        core.configure(_validCore(10_001), false, true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.checkpoint();
        assertEq(core.writes(), 0, "Core must run under STATICCALL");
        assertEq(_stateDigest(), before_);
        nft.configure(abi.encode(uint256(1)), false, true);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.nftBalance(player);
        assertEq(nft.writes(), 0, "NFT must run under STATICCALL");
        nft.configure(abi.encode(uint256(1)), true, false);
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.nftBalance(player);
    }

    function testReaderGasExhaustionReturnsNamedErrorWithinCallerBudget() public {
        ExhaustingExternalReader exhausted = new ExhaustingExternalReader();
        SeedLedger probe = new SeedLedger(address(this), address(exhausted), address(exhausted));
        (bool ok, bytes memory result) =
            address(probe).call{gas: 1_000_000}(abi.encodeCall(probe.checkpoint, ()));
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(SeedLedger.ExternalReadFailed.selector));
        assertEq(probe.observationCount(), 0);
        (ok, result) = address(probe).staticcall{gas: 500_000}(abi.encodeCall(probe.nftBalance, (player)));
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(SeedLedger.ExternalReadFailed.selector));
    }

    function testBadNFTAtRepointRollsBackTentativeCoreRebaselineAndKeepsProposal() public {
        ScriptedExternalReader nextCore = new ScriptedExternalReader();
        ScriptedExternalReader nextNFT = new ScriptedExternalReader();
        nextCore.configure(_validCore(7), false, false);
        nextNFT.configure(new bytes(31), false, false);
        ledger.proposeRepoint(address(nextCore), address(nextNFT));
        uint256 deadline = ledger.repointAfter();
        vm.warp(deadline);
        bytes32 before_ = _stateDigest();
        vm.expectRevert(SeedLedger.ExternalReadFailed.selector);
        ledger.applyRepoint();
        assertEq(_stateDigest(), before_, "tentative rebaseline must roll back");
        assertEq(ledger.core(), address(core));
        assertEq(ledger.squeek(), address(nft));
        assertEq(ledger.pendingCore(), address(nextCore));
        assertEq(ledger.pendingSqueek(), address(nextNFT));
        assertEq(ledger.repointAfter(), deadline);
        nextNFT.configure(abi.encode(uint256(0)), false, false);
        ledger.applyRepoint();
        assertEq(ledger.lastCumulativeWork(), 7);
        ledger.checkpoint();
        assertEq(ledger.lastWork(), 0, "new stream history must not become a reward");
    }
}
