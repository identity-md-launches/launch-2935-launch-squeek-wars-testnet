// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameErrors as E} from "./libraries/GameErrors.sol";

import {GameTypes as G} from "./libraries/GameTypes.sol";

/// @notice Stateless, immutable economy tables. Amounts are millionths of one game resource.
contract GameRules {
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant MAX_LEVEL = 10;
    uint256 public constant MAX_STORAGE_LEVEL = 20;
    uint256 public constant MAX_TROOPS = 1_000_000;
    uint256 public constant NFT_COUNT_PRECISION = 32;

    function grow(uint256 base, uint256 n, uint256 d, uint256 exponent) public pure returns (uint256) {
        require(exponent <= 20, E.ExponentOutOfBounds());
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
        require(field < 8 && level > 0 && level <= 10, E.InvalidField());
        // Each column packs the original costs in 8-bit entries, lowest entry first.
        uint256[4] memory bases =
            [uint256(0x322d2d1e), uint256(0x2d2d1432), uint256(0x2d14322d), uint256(0xa322d28)];
        for (uint256 i; i < 4; ++i) {
            cost[i] = grow(((bases[i] >> (8 * uint256(field / 2))) & 255) * UNIT, 16, 10, level - 1);
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
            E.InvalidBuilding()
        );
        // Each column packs the original costs in 16-bit entries, lowest entry first.
        uint256[4] memory bases = [
            uint256(0x9600be008200a0009600460046006e0064005000b4),
            uint256(0xc800c8006e00a00096006e003c0064006e003c00aa),
            uint256(0x9600b4008c00aa0082004600500064005a00dc00b4),
            uint256(0x960082010400d200aa00320032005a0064008c00aa)
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
            cost[i] = grow(((bases[i] >> (16 * uint256(kind))) & 65535) * UNIT, growth, 100, level - 1);
        }
        seconds_ = grow(duration * UNIT, timeGrowth, 100, level - 1) / UNIT;
    }

    function researchQuote(uint8 tier)
        external
        pure
        returns (uint256[4] memory cost, uint256 seed, uint256 seconds_, uint8 academy)
    {
        require(tier > 0 && tier <= 5, E.InvalidTier());
        uint256 each = grow(150 * UNIT, 22, 10, tier - 1);
        for (uint256 i; i < 4; ++i) {
            cost[i] = each;
        }
        seed = 300 * UNIT * (2 ** (tier - 1));
        seconds_ = grow(7200 * UNIT, 18, 10, tier - 1) / UNIT;
        academy = uint8(((uint256(0x806040201) >> (8 * uint256(tier - 1))) & 255));
    }

    function fieldRate(uint8 level) external pure returns (uint256) {
        require(level > 0 && level <= 10, E.InvalidFieldLevel());
        return grow(18 * UNIT, 14, 10, level - 1);
    }

    function capacity(uint8 kind, uint8 level) public pure returns (uint256 total) {
        require(kind < 3 && level <= (kind == 2 ? 10 : 20), E.InvalidCapacity());
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
        require(townHall > 0 && townHall <= 10, E.InvalidTownHall());
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
        require(kind < 7, E.InvalidUnit());
        attack = ((uint256(0x1e5a4b0f1428) >> (8 * uint256(kind))) & 255);
        defense = ((uint256(0x50a3214460f23) >> (8 * uint256(kind))) & 255);
        speed = ((uint256(0x10030e06050806) >> (8 * uint256(kind))) & 255);
        carry = ((uint256(0x5028147832) >> (8 * uint256(kind))) & 255);
        room = ((uint256(0x1040201010101) >> (8 * uint256(kind))) & 255);
        seconds_ = ((uint256(0x8462314120c0f) >> (8 * uint256(kind))) & 255) * 60;
    }

    function unitQuote(uint8 kind, uint8 barracks, uint8 tier, uint32 count)
        external
        pure
        returns (uint256[4] memory cost, uint256 duration, uint256 rooms)
    {
        require(
            kind < 7 && barracks > 0 && barracks <= 10 && count > 0 && count <= MAX_TROOPS,
            E.InvalidTraining()
        );
        require(
            tier >= uint8(((uint256(0x2040302020100) >> (8 * uint256(kind))) & 255)), E.ResearchRequired()
        );
        // Each column packs the original costs in 16-bit entries, lowest entry first.
        uint256[4] memory bases = [
            uint256(0x1e014000780037003c00370032),
            uint256(0x28008c00820037002d0037002d),
            uint256(0x14012c005a00230046001e002d),
            uint256(0x2800aa00aa0064002d00140028)
        ];
        for (uint256 i; i < 4; ++i) {
            cost[i] = ((bases[i] >> (16 * uint256(kind))) & 65535) * UNIT * count;
        }
        (,,,, uint256 room, uint256 time_) = unitStats(kind);
        rooms = room * count;
        duration = G.ceilDiv(grow(time_ * UNIT, 9, 10, barracks - 1) * count, UNIT);
    }

    function unitValue(uint8 kind) external pure returns (uint256) {
        require(kind < 7, E.InvalidUnit());
        return ((uint256(0x8203a201fe00f500dc00a000b4) >> (16 * uint256(kind))) & 65535);
    }
}
