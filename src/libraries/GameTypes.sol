// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameErrors as E} from "./GameErrors.sol";

library GameTypes {
    uint256 internal constant U = 1_000_000;
    uint256 internal constant MAP_MULTIPLIER = 7919;
    uint256 internal constant MAP_OFFSET = 1237;
    uint8 internal constant TH = 0;
    uint8 internal constant WALLS = 1;
    uint8 internal constant WHEEL = 2;
    uint8 internal constant STORE = 3;
    uint8 internal constant VAULT = 4;
    uint8 internal constant BURROW = 5;
    uint8 internal constant BARRACKS = 6;
    uint8 internal constant ACADEMY = 7;
    uint8 internal constant FORGE = 8;
    uint8 internal constant CLAN = 9;
    uint8 internal constant MARKET = 10;

    struct Context {
        bool exists;
        uint16 tile;
        uint8 townHall;
        uint8 walls;
        uint8 forge;
        uint8 barracks;
        uint8 research;
        uint256 room;
        uint64 shieldUntil;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = (x + 1) / 2;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }

    function nameKey(string memory name, uint256 maximum) internal pure returns (bytes32) {
        bytes memory b = bytes(name);
        require(b.length >= 3 && b.length <= maximum, E.InvalidNameLength());
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            require(
                (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95,
                E.InvalidNameCharacter()
            );
            if (c >= 65 && c <= 90) b[i] = bytes1(c + 32);
        }
        return keccak256(b);
    }

    /// @dev 7919 is coprime with 10000, so this affine permutation visits every tile once.
    function tile(uint256 slot) internal pure returns (uint16) {
        return uint16((slot * MAP_MULTIPLIER + MAP_OFFSET) % 10000);
    }
}
