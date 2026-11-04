// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameTest} from "./helpers/GameTest.sol";
import {GameRules} from "../src/GameRules.sol";
import {SeedLedger} from "../src/SeedLedger.sol";
import {Clans} from "../src/Clans.sol";
import {Army} from "../src/Army.sol";
import {Villages} from "../src/Villages.sol";

contract DeploymentTest is GameTest {
    function testAllConstructorsWorkWithAbsentDependencyCodeAndExplicitOwner() public {
        address absent = address(0x100123);
        SeedLedger l = new SeedLedger(owner, absent, absent);
        Army a = new Army(GameRules(absent), SeedLedger(absent), Clans(absent));
        Villages v = new Villages(GameRules(absent), SeedLedger(absent), Clans(absent), Army(absent));
        assertEq(l.owner(), owner);
        assertEq(l.core(), absent);
        assertEq(address(a.rules()), absent);
        assertEq(address(v.army()), absent);
    }

    function testDeployedSizeAndReachableOpcodes() public view {
        address[5] memory apps =
            [address(game), address(army), address(ledger), address(clans), address(rules)];
        uint256 combined;
        for (uint256 i; i < apps.length; ++i) {
            bytes memory code = apps[i].code;
            combined += code.length;
            assertGt(code.length, 0);
            assertLe(code.length, 24576);
            bool reachable = true;
            for (uint256 j; j < code.length; ++j) {
                uint8 op = uint8(code[j]);
                if (op == 0x5b) reachable = true;
                if (op >= 0x60 && op <= 0x7f) {
                    j += op - 0x5f;
                    continue;
                }
                if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "Forbidden opcode");
                if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) {
                    reachable = false;
                }
            }
        }
        assertLe(combined, 52_000, "combined launch runtime budget");
    }

    function testInvalidConstructorsRejectZeroDependencies() public {
        vm.expectRevert();
        new SeedLedger(address(0), address(core), address(nft));
        vm.expectRevert();
        new SeedLedger(owner, address(0), address(nft));
        vm.expectRevert();
        new Army(GameRules(address(0)), ledger, clans);
        vm.expectRevert();
        new Villages(rules, ledger, clans, Army(address(0)));
    }
}
