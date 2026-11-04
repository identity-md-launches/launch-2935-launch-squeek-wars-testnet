// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {GameRules} from "../src/GameRules.sol";
import {SeedLedger} from "../src/SeedLedger.sol";
import {Clans} from "../src/Clans.sol";
import {Army} from "../src/Army.sol";
import {Villages} from "../src/Villages.sol";

/// @dev Local deployment rehearsal only. All five constructors run inside a single factory call.
contract LaunchBudgetProbe {
    function deployAll(bytes[] memory codes) external returns (address[5] memory deployed) {
        require(codes.length == 5);
        for (uint256 i; i < 5; ++i) {
            bytes memory code = codes[i];
            require(code.length <= 49_152);
            address created;
            assembly ("memory-safe") { created := create2(0, add(code, 32), mload(code), i) }
            require(created != address(0) && created.code.length != 0);
            deployed[i] = created;
        }
    }
}

contract LaunchBudgetTest is Test {
    function _predict(address factory, bytes memory code, uint256 salt) private pure returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, keccak256(code)))))
            );
    }

    function testFactoryGraphOwnerAndConservativeLaunchGas() public {
        vm.chainId(11155111);
        LaunchBudgetProbe factory = new LaunchBudgetProbe();
        // A test-only paying wallet; the manifest continues to resolve the real wallet as $owner.
        address payingWallet = makeAddr("paying-wallet");
        address core = address(bytes20(hex"980b4424c007caf7a1f3670b48c8eaef7ebc3d44"));
        address nft = address(bytes20(hex"cb98349c134ab983da5bfd80527dfe2552bdb70f"));
        bytes[] memory codes = new bytes[](5);
        address[5] memory predicted;
        codes[0] = type(GameRules).creationCode;
        predicted[0] = _predict(address(factory), codes[0], 0);
        codes[1] = abi.encodePacked(type(SeedLedger).creationCode, abi.encode(payingWallet, core, nft));
        predicted[1] = _predict(address(factory), codes[1], 1);
        codes[2] = type(Clans).creationCode;
        predicted[2] = _predict(address(factory), codes[2], 2);
        codes[3] =
            abi.encodePacked(type(Army).creationCode, abi.encode(predicted[0], predicted[1], predicted[2]));
        predicted[3] = _predict(address(factory), codes[3], 3);
        codes[4] = abi.encodePacked(
            type(Villages).creationCode, abi.encode(predicted[0], predicted[1], predicted[2], predicted[3])
        );
        predicted[4] = _predict(address(factory), codes[4], 4);
        uint256 beforeGas = gasleft();
        address[5] memory deployed = factory.deployAll(codes);
        uint256 executionGas = beforeGas - gasleft();
        uint256 runtimeBytes;
        for (uint256 i; i < 5; ++i) {
            assertEq(deployed[i], predicted[i]);
            assertLe(deployed[i].code.length, 24_576);
            runtimeBytes += deployed[i].code.length;
        }
        SeedLedger ledger = SeedLedger(deployed[1]);
        Army army = Army(deployed[3]);
        Villages game = Villages(deployed[4]);
        assertEq(ledger.owner(), payingWallet);
        assertTrue(ledger.owner() != address(factory));
        assertEq(ledger.core(), core);
        assertEq(ledger.squeek(), nft);
        assertEq(address(army.rules()), deployed[0]);
        assertEq(address(army.ledger()), deployed[1]);
        assertEq(address(army.clans()), deployed[2]);
        assertEq(address(game.rules()), deployed[0]);
        assertEq(address(game.ledger()), deployed[1]);
        assertEq(address(game.clans()), deployed[2]);
        assertEq(address(game.army()), deployed[3]);
        assertLe(runtimeBytes, 52_000);
        // Cancun already charged 200 gas per runtime byte. Add 1,500 to model the brief's
        // approximately 1,700, plus pessimistic all-nonzero calldata and 500,000 factory overhead.
        uint256 calldataBytes = abi.encodeCall(factory.deployAll, (codes)).length;
        uint256 estimate = executionGas + 1_500 * runtimeBytes + 21_000 + 16 * calldataBytes + 500_000;
        emit log_named_uint("Combined runtime bytes", runtimeBytes);
        emit log_named_uint("Local CREATE2 execution gas", executionGas);
        emit log_named_uint("Factory calldata bytes", calldataBytes);
        emit log_named_uint("Conservative launch gas estimate", estimate);
        assertLt(estimate, 90_000_000);
    }
}
