// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {ModuleCalls} from "../src/libraries/ModuleCalls.sol";
import {GameTypes as G} from "../src/libraries/GameTypes.sol";

interface IModuleReply {
    function number() external view returns (uint256);
    function context() external view returns (G.Context memory);
    function flag() external view returns (bool);
    function mutate() external;
    function result() external returns (uint256);
}

contract ModuleReply {
    bytes private reply;
    bool private fail;
    bool private write;
    uint256 public writes;

    function configure(bytes memory data, bool fail_, bool write_) external {
        reply = data;
        fail = fail_;
        write = write_;
    }

    fallback() external {
        if (write) ++writes;
        bytes memory data = reply;
        bool revert_ = fail;
        assembly ("memory-safe") {
            if revert_ { revert(add(data, 32), mload(data)) }
            return(add(data, 32), mload(data))
        }
    }
}

contract ModuleCallsHarness {
    function number(address target, bool compact) external view returns (uint256) {
        if (!compact) return IModuleReply(target).number();
        return abi.decode(ModuleCalls.read(target, abi.encodeCall(IModuleReply.number, ()), 32), (uint256));
    }

    function context(address target, bool compact) external view returns (G.Context memory) {
        if (!compact) return IModuleReply(target).context();
        return
            abi.decode(ModuleCalls.read(target, abi.encodeCall(IModuleReply.context, ()), 288), (G.Context));
    }

    function flag(address target, bool compact) external view returns (bool) {
        if (!compact) return IModuleReply(target).flag();
        return abi.decode(ModuleCalls.read(target, abi.encodeCall(IModuleReply.flag, ()), 32), (bool));
    }

    function mutate(address target, bool compact) external {
        if (!compact) IModuleReply(target).mutate();
        else ModuleCalls.invoke(target, abi.encodeCall(IModuleReply.mutate, ()), 0);
    }

    function result(address target, bool compact) external returns (uint256) {
        if (!compact) return IModuleReply(target).result();
        return abi.decode(ModuleCalls.invoke(target, abi.encodeCall(IModuleReply.result, ()), 32), (uint256));
    }
}

contract ModuleCallsTest is Test {
    ModuleReply private reply = new ModuleReply();
    ModuleCallsHarness private harness = new ModuleCallsHarness();

    function _compare(bytes4 selector, address target) private {
        uint256 checkpoint = vm.snapshotState();
        (bool originalOK, bytes memory original) =
            address(harness).call{gas: 1_000_000}(abi.encodeWithSelector(selector, target, false));
        uint256 writes = reply.writes();
        assertTrue(vm.revertToState(checkpoint));
        (bool compactOK, bytes memory compact) =
            address(harness).call{gas: 1_000_000}(abi.encodeWithSelector(selector, target, true));
        assertEq(compactOK, originalOK, "success changed");
        assertEq(compact, original, "return/revert data changed");
        assertEq(reply.writes(), writes, "mutation/rollback changed");
    }

    function testTypedReadsAndWritesMatchHighLevelCalls() public {
        reply.configure(abi.encode(uint256(123)), false, false);
        _compare(harness.number.selector, address(reply));
        _compare(harness.result.selector, address(reply));
        reply.configure(abi.encode(true), false, false);
        _compare(harness.flag.selector, address(reply));
        G.Context memory c = G.Context(true, 9999, 10, 9, 8, 7, 5, 123456, 987654321);
        reply.configure(abi.encode(c), false, false);
        _compare(harness.context.selector, address(reply));
        reply.configure(abi.encode(uint256(123)), false, true);
        _compare(harness.result.selector, address(reply));
        _compare(harness.mutate.selector, address(reply));
    }

    function testAbsentCodeAndShortRepliesMatchHighLevelCalls() public {
        _compare(harness.number.selector, address(0xAA123));
        _compare(harness.result.selector, address(0xAA123));
        _compare(harness.mutate.selector, address(0xAA123));
        for (uint256 length; length < 32; ++length) {
            reply.configure(new bytes(length), false, true);
            _compare(harness.result.selector, address(reply));
            assertEq(reply.writes(), 0, "short result must roll back the call");
            reply.configure(new bytes(length), false, false);
            _compare(harness.number.selector, address(reply));
        }
        reply.configure(new bytes(287), false, false);
        _compare(harness.context.selector, address(reply));
    }

    function testMalformedBoolAndContextWidthsAreStillRejected() public {
        reply.configure(abi.encode(uint256(2)), false, false);
        _compare(harness.flag.selector, address(reply));
        uint256[9] memory words;
        uint256[9] memory widths =
            [uint256(1), 65535, 255, 255, 255, 255, 255, type(uint256).max, type(uint64).max];
        for (uint256 i; i < 9; ++i) {
            if (i == 7) continue;
            words[i] = widths[i] + 1;
            reply.configure(abi.encode(words), false, false);
            _compare(harness.context.selector, address(reply));
            words[i] = 0;
        }
    }

    function testTrailingReturnDataIsIgnoredAndReadsRemainStatic() public {
        reply.configure(abi.encode(uint256(123), uint256(456)), false, false);
        _compare(harness.number.selector, address(reply));
        _compare(harness.result.selector, address(reply));
        reply.configure(abi.encode(uint256(123)), false, true);
        _compare(harness.number.selector, address(reply));
        assertEq(reply.writes(), 0);
    }

    function testFuzzRevertBytesBubbleAndMutationsRollBack(bytes memory data) public {
        reply.configure(data, true, true);
        _compare(harness.result.selector, address(reply));
        _compare(harness.mutate.selector, address(reply));
        assertEq(reply.writes(), 0);
        reply.configure(data, true, false);
        _compare(harness.number.selector, address(reply));
        _compare(harness.context.selector, address(reply));
    }
}
