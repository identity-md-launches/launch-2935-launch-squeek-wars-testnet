// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {GameRules} from "../src/GameRules.sol";
import {ReferenceRules} from "./helpers/ReferenceRules.sol";

contract RulesEncodingTest is Test {
    GameRules private rules = new GameRules();
    ReferenceRules private referenceRules = new ReferenceRules();

    function _equal(bytes memory input) private view {
        (bool compactOK, bytes memory compact) = address(rules).staticcall(input);
        (bool originalOK, bytes memory original) = address(referenceRules).staticcall(input);
        assertTrue(originalOK, "valid reference input");
        assertTrue(compactOK, "valid compact input");
        assertEq(compact, original, "original table/formula changed");
    }

    function testEveryFieldAndBuildingQuoteMatchesOriginal() public view {
        for (uint8 level = 1; level <= 10; ++level) {
            _equal(abi.encodeCall(rules.fieldRate, (level)));
            for (uint8 field; field < 8; ++field) {
                _equal(abi.encodeCall(rules.fieldQuote, (field, level)));
            }
        }
        for (uint8 kind; kind < 11; ++kind) {
            uint8 maxLevel = kind == 3 || kind == 4 ? 20 : 10;
            for (uint8 level = 1; level <= maxLevel; ++level) {
                _equal(abi.encodeCall(rules.buildingQuote, (kind, level)));
            }
        }
        for (uint8 tier = 1; tier <= 5; ++tier) {
            _equal(abi.encodeCall(rules.researchQuote, (tier)));
        }
        for (uint8 kind; kind < 3; ++kind) {
            for (uint8 level; level <= (kind == 2 ? 10 : 20); ++level) {
                _equal(abi.encodeCall(rules.capacity, (kind, level)));
            }
        }
    }

    function testEveryUnitTrainingLevelAndUnlockMatchesOriginal() public view {
        uint8[7] memory requiredTier = [uint8(0), 1, 2, 2, 3, 4, 2];
        uint32[3] memory counts = [uint32(1), 41, 1_000_000];
        for (uint8 kind; kind < 7; ++kind) {
            _equal(abi.encodeCall(rules.unitStats, (kind)));
            _equal(abi.encodeCall(rules.unitValue, (kind)));
            for (uint8 barracks = 1; barracks <= 10; ++barracks) {
                for (uint8 tier; tier <= 5; ++tier) {
                    for (uint256 i; i < counts.length; ++i) {
                        bytes memory input =
                            abi.encodeCall(rules.unitQuote, (kind, barracks, tier, counts[i]));
                        if (tier >= requiredTier[kind]) {
                            _equal(input);
                        } else {
                            (bool ok,) = address(rules).staticcall(input);
                            assertFalse(ok, "locked unit became trainable");
                        }
                    }
                }
            }
        }
    }

    function testFuzzBuildDurationExactlyMatchesOriginal(uint32 base, uint8 hall, uint256 nfts, uint256 work)
        public
        view
    {
        hall = uint8(bound(hall, 1, 10));
        _equal(abi.encodeCall(rules.buildDuration, (base, hall, nfts, work)));
    }
}
