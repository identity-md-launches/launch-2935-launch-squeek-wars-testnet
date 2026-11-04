// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ModuleCalls} from "./libraries/ModuleCalls.sol";

import {GameErrors as E} from "./libraries/GameErrors.sol";

import {GameTypes as G} from "./libraries/GameTypes.sol";
import {Guard} from "./libraries/Guard.sol";
import {GameRules} from "./GameRules.sol";
import {SeedLedger} from "./SeedLedger.sol";
import {Clans} from "./Clans.sol";
import {Army} from "./Army.sol";

/// @notice Canonical player entry point. Every player action derives the village from msg.sender.
contract Villages is Guard {
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant VILLAGE_LIMIT = 9800;
    uint256 public constant MAX_MARKET_LOTS = 1_000_000;
    GameRules public immutable rules;
    SeedLedger public immutable ledger;
    Clans public immutable clans;
    Army public immutable army;
    uint256 public villageCount;
    uint256 public immutable seasonStartedAt;

    struct Village {
        string name;
        uint16 tile;
        uint64 foundedAt;
        uint64 lastAccrued;
        uint64 shieldUntil;
        uint64 peaceUsedAt;
        uint64 boostUntil;
        uint64 repairAt;
        uint8 boostResource;
        uint8 tier;
        uint8 damagedWalls;
        bool banner;
        uint8[8] fields;
        uint8[11] buildings;
        uint256[4] stock;
        uint256[4] remainder;
        uint256 upkeepRemainder;
    }

    struct BuildOrder {
        uint8 target;
        uint8 level;
        uint64 readyAt;
        uint256[4] cost;
        uint256 seed;
    }

    struct Study {
        uint8 tier;
        uint64 readyAt;
        uint256 spent;
    }
    mapping(address => Village) private villages;
    mapping(address => BuildOrder[2]) private builds;
    mapping(address => Study) private studies;
    mapping(bytes32 => address) public nameOwner;
    mapping(uint16 => address) public tileOwner;

    error NoVillage();
    error OnlyArmy();
    error InvalidAction();
    error NotReady();
    error InsufficientResources();

    event Founded(address indexed player, string name, uint16 tile);
    event Accrued(address indexed player, uint256[4] stock);
    event BuildOrdered(
        address indexed player, uint8 indexed slot, uint8 target, uint8 level, uint256 readyAt
    );
    event BuildCompleted(address indexed player, uint8 indexed slot, uint8 target, uint8 level);
    event BuildCancelled(address indexed player, uint8 indexed slot);
    event ResearchOrdered(address indexed player, uint8 tier, uint256 readyAt);
    event ResearchCompleted(address indexed player, uint8 tier);
    event Exchanged(address indexed player, uint8 input, uint8 output, uint256 lots, uint256 received);
    event TreasuryUsed(address indexed player, uint8 kind, uint8 resource, uint256 until);
    event WallsDamaged(address indexed player, uint8 remainingDamage, uint256 nextRepair);

    constructor(GameRules rules_, SeedLedger ledger_, Clans clans_, Army army_) {
        require(
            address(rules_) != address(0) && address(ledger_) != address(0) && address(clans_) != address(0)
                && address(army_) != address(0),
            E.InvalidDependency()
        );
        rules = rules_;
        ledger = ledger_;
        clans = clans_;
        army = army_;
        seasonStartedAt = block.timestamp;
    }
    modifier player() {
        if (villages[msg.sender].foundedAt == 0) revert NoVillage();
        _;
    }
    modifier onlyArmy() {
        if (msg.sender != address(army)) revert OnlyArmy();
        _;
    }

    function village(address who) external view returns (Village memory) {
        return villages[who];
    }

    function buildOrder(address who, uint8 slot) external view returns (BuildOrder memory) {
        require(slot < 2, E.InvalidSlot());
        return builds[who][slot];
    }

    function study(address who) external view returns (Study memory) {
        return studies[who];
    }

    function seedBalance(address who) external view returns (uint256) {
        return abi.decode(
            ModuleCalls.read(address(ledger), abi.encodeCall(ledger.balanceOf, (address(this), who)), 32),
            (uint256)
        );
    }

    function tileForSlot(uint256 slot) external pure returns (uint16) {
        require(slot < 10000, E.InvalidSlot());
        return G.tile(slot);
    }

    function campTile(uint256 campId) external pure returns (uint16) {
        require(campId < 200, E.InvalidCamp());
        return G.tile(campId * 50 + 49);
    }

    function found(string calldata name) external nonReentrant {
        if (villages[msg.sender].foundedAt != 0 || villageCount >= VILLAGE_LIMIT) revert InvalidAction();
        bytes32 key = G.nameKey(name, 16);
        require(nameOwner[key] == address(0), E.NameTaken());
        uint256 slot = villageCount + villageCount / 49;
        uint16 tile = G.tile(slot);
        Village storage v = villages[msg.sender];
        v.name = name;
        v.tile = tile;
        v.foundedAt = uint64(block.timestamp);
        v.lastAccrued = uint64(block.timestamp);
        v.shieldUntil = uint64(block.timestamp + 7 days);
        v.buildings[G.TH] = 1;
        v.buildings[G.WALLS] = 1;
        for (uint256 i; i < 8; ++i) {
            v.fields[i] = 1;
        }
        for (uint256 i; i < 4; ++i) {
            v.stock[i] = 750 * UNIT;
        }
        nameOwner[key] = msg.sender;
        tileOwner[tile] = msg.sender;
        ++villageCount;
        ModuleCalls.invoke(address(ledger), abi.encodeCall(ledger.register, (msg.sender)), 0);
        emit Founded(msg.sender, name, tile);
    }

    function claimSeed() external player nonReentrant returns (uint256 seed, uint256 xp) {
        (seed, xp) = abi.decode(
            ModuleCalls.invoke(address(ledger), abi.encodeCall(ledger.claim, (msg.sender)), 64),
            (uint256, uint256)
        );
        ModuleCalls.invoke(address(army), abi.encodeCall(army.creditXP, (msg.sender, xp)), 0);
    }

    function sync(address who) external nonReentrant {
        _accrue(who);
    }

    function storageCapacity(address who) public view returns (uint256) {
        return abi.decode(
            ModuleCalls.read(
                address(rules), abi.encodeCall(rules.capacity, (0, villages[who].buildings[G.STORE])), 32
            ),
            (uint256)
        );
    }

    function vaultProtection(address who) public view returns (uint256) {
        return abi.decode(
            ModuleCalls.read(
                address(rules), abi.encodeCall(rules.capacity, (1, villages[who].buildings[G.VAULT])), 32
            ),
            (uint256)
        );
    }

    function roomCapacity(address who) public view returns (uint256) {
        return abi.decode(
            ModuleCalls.read(
                address(rules), abi.encodeCall(rules.capacity, (2, villages[who].buildings[G.BURROW])), 32
            ),
            (uint256)
        );
    }

    function stock(address who) external view returns (uint256[4] memory amounts) {
        (amounts,,) = _production(who);
    }

    function _production(address who)
        private
        view
        returns (uint256[4] memory amounts, uint256[4] memory remainder, uint256 upkeepRemainder)
    {
        Village storage v = villages[who];
        if (v.foundedAt == 0) revert NoVillage();
        amounts = v.stock;
        remainder = v.remainder;
        upkeepRemainder = v.upkeepRemainder;
        uint256 elapsed = block.timestamp - v.lastAccrued;
        if (elapsed == 0) return (amounts, remainder, upkeepRemainder);
        uint256 integralStart = _wheelIntegral(v.buildings[G.WHEEL], v.lastAccrued);
        uint256 weighted =
            elapsed * UNIT + _wheelIntegral(v.buildings[G.WHEEL], block.timestamp) - integralStart;
        uint256 boosted;
        if (v.boostUntil > v.lastAccrued) {
            uint256 end = G.min(block.timestamp, v.boostUntil);
            boosted = (end - v.lastAccrued) * UNIT + _wheelIntegral(v.buildings[G.WHEEL], end) - integralStart;
        }
        uint256 cap = storageCapacity(who);
        for (uint8 i; i < 4; ++i) {
            uint256 rate = abi.decode(
                ModuleCalls.read(address(rules), abi.encodeCall(rules.fieldRate, (v.fields[i * 2])), 32),
                (uint256)
            )
            + abi.decode(
                ModuleCalls.read(address(rules), abi.encodeCall(rules.fieldRate, (v.fields[i * 2 + 1])), 32),
                (uint256)
            );
            uint256 numerator = rate * (weighted * 4 + (i == v.boostResource ? boosted : 0)) + remainder[i];
            amounts[i] += numerator / (14400 * UNIT);
            remainder[i] = numerator % (14400 * UNIT);
        }
        uint256 upkeep = elapsed
            * abi.decode(
                ModuleCalls.read(address(army), abi.encodeCall(army.allocatedRoom, (address(this), who)), 32),
                (uint256)
            ) * UNIT + upkeepRemainder;
        uint256 foodCost = upkeep / 7200;
        upkeepRemainder = upkeep % 7200;
        amounts[1] = amounts[1] > foodCost ? amounts[1] - foodCost : 0;
        if (amounts[1] == 0) upkeepRemainder = 0;
        for (uint8 i; i < 4; ++i) {
            if (amounts[i] >= cap) {
                amounts[i] = cap;
                remainder[i] = 0;
            }
        }
    }

    function _accrue(address who) private {
        Village storage v = villages[who];
        (v.stock, v.remainder, v.upkeepRemainder) = _production(who);
        v.lastAccrued = uint64(block.timestamp);
        emit Accrued(who, v.stock);
    }

    function _spend(address who, uint256[4] memory cost) private {
        Village storage v = villages[who];
        for (uint8 i; i < 4; ++i) {
            if (v.stock[i] < cost[i]) revert InsufficientResources();
            v.stock[i] -= cost[i];
        }
    }

    function _credit(address who, uint256[4] memory amounts) private {
        uint256 cap = storageCapacity(who);
        for (uint8 i; i < 4; ++i) {
            villages[who].stock[i] = G.min(cap, villages[who].stock[i] + amounts[i]);
        }
    }

    function _spent(uint256[4] memory amounts, uint256 seed) private pure returns (uint256) {
        return amounts[0] + amounts[1] + amounts[2] + amounts[3] + seed;
    }

    /// @notice Targets 0..7 are fields; 8..18 are buildings in GameTypes order.
    function orderBuild(uint8 target, uint8 slot) external player nonReentrant {
        require(target < 19 && slot < 2 && builds[msg.sender][slot].readyAt == 0, E.InvalidBuildSlot());
        for (uint8 i; i < 2; ++i) {
            require(
                builds[msg.sender][i].readyAt == 0 || builds[msg.sender][i].target != target,
                E.AlreadyBuildingTarget()
            );
        }
        Village storage v = villages[msg.sender];
        uint8 level;
        uint256[4] memory cost;
        uint256 seed;
        uint256 duration;
        if (target < 8) {
            level = v.fields[target] + 1;
            require(level <= 10 && level <= v.buildings[G.TH], E.FieldCappedByTownHall());
            (cost, duration) = abi.decode(
                ModuleCalls.read(address(rules), abi.encodeCall(rules.fieldQuote, (target, level)), 160),
                (uint256[4], uint256)
            );
        } else {
            uint8 kind = target - 8;
            level = v.buildings[kind] + 1;
            require(level <= ((kind == G.STORE || kind == G.VAULT) ? 20 : 10), E.MaxLevel());
            if (kind != G.TH) {
                require(
                    level <= v.buildings[G.TH] * ((kind == G.STORE || kind == G.VAULT) ? 2 : 1),
                    E.BuildingCappedByTownHall()
                );
            }
            if (kind == G.VAULT) require(v.tier >= 1, E.ResearchVaultFirst());
            if (kind == G.FORGE || kind == G.CLAN) require(v.tier >= 2, E.ResearchTier2First());
            if (level == 1) {
                uint256 plots;
                for (uint8 i; i < 11; ++i) {
                    if (v.buildings[i] != 0) ++plots;
                }
                for (uint8 i; i < 2; ++i) {
                    if (
                        builds[msg.sender][i].readyAt != 0 && builds[msg.sender][i].target >= 8
                            && builds[msg.sender][i].level == 1
                    ) ++plots;
                }
                require(plots < G.min(12, 3 + v.buildings[G.TH]), E.NoPlotAvailable());
            }
            (cost, seed, duration) = abi.decode(
                ModuleCalls.read(address(rules), abi.encodeCall(rules.buildingQuote, (kind, level)), 192),
                (uint256[4], uint256, uint256)
            );
        }
        duration = abi.decode(
            ModuleCalls.read(
                address(rules),
                abi.encodeCall(
                    rules.buildDuration,
                    (
                        duration,
                        v.buildings[G.TH],
                        abi.decode(
                            ModuleCalls.read(
                                address(ledger), abi.encodeCall(ledger.nftBalance, (msg.sender)), 32
                            ),
                            (uint256)
                        ),
                        abi.decode(
                            ModuleCalls.read(address(ledger), abi.encodeCall(ledger.lastWork, ()), 32),
                            (uint256)
                        )
                    )
                ),
                32
            ),
            (uint256)
        );
        _accrue(msg.sender);
        _spend(msg.sender, cost);
        if (seed != 0) _burn(seed);
        builds[msg.sender][slot] = BuildOrder(target, level, uint64(block.timestamp + duration), cost, seed);
        emit BuildOrdered(msg.sender, slot, target, level, block.timestamp + duration);
    }

    function completeBuild(address who, uint8 slot) external nonReentrant {
        require(slot < 2, E.InvalidSlot());
        BuildOrder memory b = builds[who][slot];
        if (b.readyAt == 0 || block.timestamp < b.readyAt) revert NotReady();
        _accrue(who);
        delete builds[who][slot];
        if (b.target < 8) villages[who].fields[b.target] = b.level;
        else villages[who].buildings[b.target - 8] = b.level;
        ModuleCalls.invoke(address(clans), abi.encodeCall(clans.record, (who, 0, _spent(b.cost, b.seed))), 0);
        emit BuildCompleted(who, slot, b.target, b.level);
    }

    function cancelBuild(uint8 slot) external player nonReentrant {
        require(slot < 2, E.InvalidSlot());
        BuildOrder memory b = builds[msg.sender][slot];
        require(b.readyAt != 0 && block.timestamp < b.readyAt, E.CannotCancelCompletedBuild());
        delete builds[msg.sender][slot];
        _accrue(msg.sender);
        for (uint8 i; i < 4; ++i) {
            b.cost[i] = b.cost[i] * 80 / 100;
        }
        _credit(msg.sender, b.cost);
        if (b.seed != 0) {
            ModuleCalls.invoke(
                address(ledger), abi.encodeCall(ledger.refund, (msg.sender, b.seed * 80 / 100)), 0
            );
        }
        emit BuildCancelled(msg.sender, slot);
    }

    function orderResearch() external player nonReentrant {
        Village storage v = villages[msg.sender];
        require(studies[msg.sender].readyAt == 0, E.ResearchBusy());
        uint8 tier = v.tier + 1;
        (uint256[4] memory cost, uint256 seed, uint256 duration, uint8 academy) = abi.decode(
            ModuleCalls.read(address(rules), abi.encodeCall(rules.researchQuote, (tier)), 224),
            (uint256[4], uint256, uint256, uint8)
        );
        require(v.buildings[G.ACADEMY] >= academy, E.AcademyTooLow());
        _accrue(msg.sender);
        _spend(msg.sender, cost);
        _burn(seed);
        studies[msg.sender] = Study(tier, uint64(block.timestamp + duration), _spent(cost, seed));
        emit ResearchOrdered(msg.sender, tier, block.timestamp + duration);
    }

    function completeResearch(address who) external nonReentrant {
        Study memory s = studies[who];
        if (s.readyAt == 0 || block.timestamp < s.readyAt) revert NotReady();
        delete studies[who];
        villages[who].tier = s.tier;
        ModuleCalls.invoke(address(clans), abi.encodeCall(clans.record, (who, 1, s.spent)), 0);
        emit ResearchCompleted(who, s.tier);
    }

    /// @notice Input 0..3 is a resource, 4 is SEED; output is always a different resource.
    function exchange(uint8 input, uint8 output, uint256 lots) external player nonReentrant {
        require(
            input < 5 && output < 4 && input != output && lots > 0 && lots <= MAX_MARKET_LOTS,
            E.InvalidExchange()
        );
        Village storage v = villages[msg.sender];
        uint8 market = v.buildings[G.MARKET];
        require(market != 0, E.MarketRequired());
        _accrue(msg.sender);
        uint256 paid = lots * 100 * UNIT;
        if (input == 4) {
            _burn(paid);
        } else {
            if (v.stock[input] < paid) revert InsufficientResources();
            v.stock[input] -= paid;
        }
        uint256 received = lots * (25 + 5 * (market - 1)) * UNIT;
        require(v.stock[output] + received <= storageCapacity(msg.sender), E.InsufficientStorage());
        v.stock[output] += received;
        emit Exchanged(msg.sender, input, output, lots, received);
    }

    /// @notice Kind 0: resource boost; 1: peace shield; 2: permanent decorative banner.
    function treasury(uint8 kind, uint8 resource) external player nonReentrant {
        Village storage v = villages[msg.sender];
        uint256 until;
        if (kind == 0) {
            require(resource < 4 && block.timestamp >= v.boostUntil, E.BoostActiveOrInvalidResource());
            _accrue(msg.sender);
            _burn(500 * UNIT);
            v.boostResource = resource;
            until = block.timestamp + 1 days;
            v.boostUntil = uint64(until);
        } else if (kind == 1) {
            require(v.peaceUsedAt == 0 || block.timestamp >= v.peaceUsedAt + 3 days, E.PeaceCooldown());
            until = block.timestamp + 12 hours;
            require(v.shieldUntil < until, E.ShieldAlreadyActive());
            _burn(4000 * UNIT);
            v.peaceUsedAt = uint64(block.timestamp);
            v.shieldUntil = uint64(until);
        } else if (kind == 2) {
            require(!v.banner, E.BannerAlreadyOwned());
            _burn(1000 * UNIT);
            v.banner = true;
        } else {
            revert InvalidAction();
        }
        emit TreasuryUsed(msg.sender, kind, resource, until);
    }

    function foundClan(string calldata name) external player nonReentrant returns (uint256) {
        return abi.decode(
            ModuleCalls.invoke(
                address(clans),
                abi.encodeCall(clans.found, (msg.sender, name, villages[msg.sender].buildings[G.CLAN])),
                32
            ),
            (uint256)
        );
    }

    function joinClan(uint256 id) external player nonReentrant {
        ModuleCalls.invoke(
            address(clans),
            abi.encodeCall(clans.join, (msg.sender, id, villages[msg.sender].buildings[G.CLAN])),
            0
        );
    }

    function inviteToClan(address who, bool open) external player nonReentrant {
        ModuleCalls.invoke(address(clans), abi.encodeCall(clans.invite, (msg.sender, who, open)), 0);
    }

    function leaveClan() external player nonReentrant {
        ModuleCalls.invoke(address(clans), abi.encodeCall(clans.leave, (msg.sender)), 0);
    }

    function raiseClanCapacity() external player nonReentrant {
        ModuleCalls.invoke(
            address(clans),
            abi.encodeCall(clans.raiseCapacity, (msg.sender, villages[msg.sender].buildings[G.CLAN])),
            0
        );
    }

    function train(uint8 kind, uint32 count) external player nonReentrant {
        ModuleCalls.invoke(address(army), abi.encodeCall(army.train, (msg.sender, kind, count)), 0);
    }

    function allocateChampion(uint8 might, uint8 attack, uint8 defense, uint8 carry)
        external
        player
        nonReentrant
    {
        ModuleCalls.invoke(
            address(army), abi.encodeCall(army.allocate, (msg.sender, might, attack, defense, carry)), 0
        );
    }

    /// @notice Modes: 1 raid, 2 scout, 3 support. campId is used only when target is zero.
    function send(address target, uint16 campId, uint32[7] calldata units, bool champion, uint8 mode)
        external
        player
        nonReentrant
        returns (uint256)
    {
        uint256 id = abi.decode(
            ModuleCalls.invoke(
                address(army),
                abi.encodeCall(army.send, (msg.sender, target, campId, units, champion, mode)),
                32
            ),
            (uint256)
        );
        if (mode == 1 || mode == 2) villages[msg.sender].shieldUntil = uint64(block.timestamp);
        return id;
    }

    function recall(uint256 movement) external player nonReentrant {
        ModuleCalls.invoke(address(army), abi.encodeCall(army.recall, (msg.sender, movement)), 0);
    }

    function effectiveWalls(address who) public view returns (uint8) {
        Village storage v = villages[who];
        uint256 damage = v.damagedWalls;
        if (damage != 0 && block.timestamp >= v.repairAt) {
            uint256 repaired = 1 + (block.timestamp - v.repairAt) / 12 hours;
            damage = damage > repaired ? damage - repaired : 0;
        }
        return uint8(v.buildings[G.WALLS] - damage);
    }

    function armyContext(address who) external view returns (G.Context memory) {
        Village storage v = villages[who];
        return G.Context(
            v.foundedAt != 0,
            v.tile,
            v.buildings[G.TH],
            effectiveWalls(who),
            v.buildings[G.FORGE],
            v.buildings[G.BARRACKS],
            v.tier,
            roomCapacity(who),
            v.shieldUntil
        );
    }

    function armyTouch(address who) external onlyArmy {
        _accrue(who);
    }

    function armySpend(address who, uint256[4] calldata cost) external onlyArmy {
        _accrue(who);
        _spend(who, cost);
    }

    function armyCredit(address who, uint256[4] calldata amounts) external onlyArmy {
        _accrue(who);
        _credit(who, amounts);
    }

    function armyRecord(address who, uint8 kind, uint256 amount) external onlyArmy {
        ModuleCalls.invoke(address(clans), abi.encodeCall(clans.record, (who, kind, amount)), 0);
    }

    function armyLoot(address who, uint256 capacity) external onlyArmy returns (uint256[4] memory taken) {
        _accrue(who);
        uint256 guard = vaultProtection(who);
        for (uint8 i; i < 4; ++i) {
            uint256 available = villages[who].stock[i] > guard ? villages[who].stock[i] - guard : 0;
            taken[i] = G.min(capacity / 4, available);
            villages[who].stock[i] -= taken[i];
        }
    }

    function armyDamageWalls(address who, uint8 damage) external onlyArmy {
        Village storage v = villages[who];
        uint8 oldDamage = v.damagedWalls;
        uint8 currentDamage = v.buildings[G.WALLS] - effectiveWalls(who);
        if (currentDamage == 0) {
            v.repairAt = uint64(block.timestamp + 12 hours);
        } else if (oldDamage != currentDamage) {
            v.repairAt += uint64(uint256(oldDamage - currentDamage) * 12 hours);
        }
        v.damagedWalls = uint8(G.min(v.buildings[G.WALLS], uint256(currentDamage) + damage));
        emit WallsDamaged(who, v.damagedWalls, v.repairAt);
    }

    function _wheelIntegral(uint8 level, uint256 timestamp) private view returns (uint256) {
        return abi.decode(
            ModuleCalls.read(address(ledger), abi.encodeCall(ledger.wheelIntegral, (level, timestamp)), 32),
            (uint256)
        );
    }

    function _burn(uint256 amount) private {
        ModuleCalls.invoke(address(ledger), abi.encodeCall(ledger.burn, (msg.sender, amount)), 0);
    }
}
