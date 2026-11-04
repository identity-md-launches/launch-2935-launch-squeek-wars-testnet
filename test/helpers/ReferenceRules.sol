// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameTypes as G} from "../../src/libraries/GameTypes.sol";

/// @dev Frozen pre-adaptation GameRules, used only to compare the compact tables against the original.
/// Not a launch application.
contract ReferenceRules {
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant MAX_LEVEL = 10;
    uint256 public constant MAX_STORAGE_LEVEL = 20;
    uint256 public constant MAX_TROOPS = 1_000_000;
    uint256 public constant NFT_COUNT_PRECISION = 32;

    function grow(uint256 base, uint256 n, uint256 d, uint256 exponent) public pure returns (uint256) {
        require(exponent <= 20, "Exponent out of bounds");
        for (uint256 i; i < exponent; ++i) {
            base = base * n / d;
        }
        return base;
    }

    function fieldQuote(uint8 field, uint8 level)
        external
        pure
        returns (uint256[4] memory cost, uint256 seconds_)
    {
        require(field < 8 && level > 0 && level <= 10, "Invalid field");
        uint256[4][4] memory bases = [
            [uint256(30), 50, 45, 40],
            [uint256(45), 20, 50, 45],
            [uint256(45), 45, 20, 50],
            [uint256(50), 45, 45, 10]
        ];
        for (uint256 i; i < 4; ++i) {
            cost[i] = grow(bases[field / 2][i] * UNIT, 16, 10, level - 1);
        }
        seconds_ = grow(1440 * UNIT, 14, 10, level - 1) / UNIT;
    }

    function buildingQuote(uint8 kind, uint8 level)
        external
        pure
        returns (uint256[4] memory cost, uint256 seed, uint256 seconds_)
    {
        require(
            kind < 11 && level > 0 && level <= ((kind == G.STORE || kind == G.VAULT) ? 20 : 10),
            "Invalid building"
        );
        uint256[4][11] memory bases = [
            [uint256(180), 170, 180, 170],
            [uint256(80), 60, 220, 140],
            [uint256(100), 110, 90, 100],
            [uint256(110), 100, 100, 90],
            [uint256(70), 60, 80, 50],
            [uint256(70), 110, 70, 50],
            [uint256(150), 150, 130, 170],
            [uint256(160), 160, 170, 210],
            [uint256(130), 110, 140, 260],
            [uint256(190), 200, 180, 130],
            [uint256(150), 200, 150, 150]
        ];
        uint256 growth = 162;
        uint256 duration = 2160;
        uint256 timeGrowth = 145;
        if (kind == G.TH) {
            growth = 175;
            duration = 2700;
            timeGrowth = 150;
            seed = grow(667 * UNIT, 15, 10, level - 1);
        }
        if (kind == G.WHEEL) {
            growth = 168;
            seed = grow(300 * UNIT, 15, 10, level - 1);
        }
        if (kind == G.STORE || kind == G.VAULT) {
            growth = 128;
            duration = 1620;
            timeGrowth = 120;
        }
        if (kind == G.BURROW) {
            growth = 155;
            duration = 1800;
        }
        for (uint256 i; i < 4; ++i) {
            cost[i] = grow(bases[kind][i] * UNIT, growth, 100, level - 1);
        }
        seconds_ = grow(duration * UNIT, timeGrowth, 100, level - 1) / UNIT;
    }

    function researchQuote(uint8 tier)
        external
        pure
        returns (uint256[4] memory cost, uint256 seed, uint256 seconds_, uint8 academy)
    {
        require(tier > 0 && tier <= 5, "Invalid tier");
        uint256 each = grow(150 * UNIT, 22, 10, tier - 1);
        for (uint256 i; i < 4; ++i) {
            cost[i] = each;
        }
        seed = 300 * UNIT * (2 ** (tier - 1));
        seconds_ = grow(7200 * UNIT, 18, 10, tier - 1) / UNIT;
        academy = [uint8(1), 2, 4, 6, 8][tier - 1];
    }

    function fieldRate(uint8 level) external pure returns (uint256) {
        require(level > 0 && level <= 10, "Invalid field level");
        return grow(18 * UNIT, 14, 10, level - 1);
    }

    function capacity(uint8 kind, uint8 level) public pure returns (uint256 total) {
        require(kind < 3 && level <= (kind == 2 ? 10 : 20), "Invalid capacity");
        total = kind == 0 ? 1500 * UNIT : kind == 1 ? 300 * UNIT : 30;
        for (uint256 i = 1; i <= level; ++i) {
            total += kind == 2
                ? grow(20 * i * UNIT, 112, 100, i - 1) / UNIT
                : grow((kind == 0 ? 1800 : 500) * UNIT, 122, 100, i - 1);
        }
    }

    function buildDuration(uint256 base, uint8 townHall, uint256 nftCount, uint256 work)
        external
        pure
        returns (uint256)
    {
        require(townHall > 0 && townHall <= 10, "Invalid town hall");
        nftCount = G.min(nftCount, NFT_COUNT_PRECISION);
        uint256 workFactor = G.min(work, 11000) * UNIT / 11000;
        uint256 reduction = 300_000 * (UNIT - UNIT / (uint256(1) << nftCount)) / UNIT * workFactor / UNIT;
        return G.ceilDiv(base * (100 - 3 * (townHall - 1)) * (UNIT - reduction), 100 * UNIT);
    }

    /// @return attack Defense, speed, carry, room and train seconds follow attack.
    function unitStats(uint8 kind)
        public
        pure
        returns (
            uint256 attack,
            uint256 defense,
            uint256 speed,
            uint256 carry,
            uint256 room,
            uint256 seconds_
        )
    {
        require(kind < 7, "Invalid unit");
        attack = [uint256(40), 20, 15, 75, 90, 30, 0][kind];
        defense = [uint256(35), 15, 70, 20, 50, 10, 5][kind];
        speed = [uint256(6), 8, 5, 6, 14, 3, 16][kind];
        carry = [uint256(50), 120, 20, 40, 80, 0, 0][kind];
        room = [uint256(1), 1, 1, 1, 2, 4, 1][kind];
        seconds_ = [uint256(15), 12, 18, 20, 35, 70, 8][kind] * 60;
    }

    function unitQuote(uint8 kind, uint8 barracks, uint8 tier, uint32 count)
        external
        pure
        returns (uint256[4] memory cost, uint256 duration, uint256 rooms)
    {
        require(
            kind < 7 && barracks > 0 && barracks <= 10 && count > 0 && count <= MAX_TROOPS, "Invalid training"
        );
        require(tier >= [uint8(0), 1, 2, 2, 3, 4, 2][kind], "Research required");
        uint256[4][7] memory bases = [
            [uint256(50), 45, 45, 40],
            [uint256(55), 55, 30, 20],
            [uint256(60), 45, 70, 45],
            [uint256(55), 55, 35, 100],
            [uint256(120), 130, 90, 170],
            [uint256(320), 140, 300, 170],
            [uint256(30), 40, 20, 40]
        ];
        for (uint256 i; i < 4; ++i) {
            cost[i] = bases[kind][i] * UNIT * count;
        }
        (,,,, uint256 room, uint256 time_) = unitStats(kind);
        rooms = room * count;
        duration = G.ceilDiv(grow(time_ * UNIT, 9, 10, barracks - 1) * count, UNIT);
    }

    function unitValue(uint8 kind) external pure returns (uint256) {
        require(kind < 7, "Invalid unit");
        return [uint256(180), 160, 220, 245, 510, 930, 130][kind];
    }
}
