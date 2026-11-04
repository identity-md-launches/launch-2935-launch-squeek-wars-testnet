// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ModuleCalls} from "./libraries/ModuleCalls.sol";

import {GameErrors as E} from "./libraries/GameErrors.sol";

import {GameTypes as G} from "./libraries/GameTypes.sol";
import {Guard} from "./libraries/Guard.sol";
import {GameRules} from "./GameRules.sol";
import {SeedLedger} from "./SeedLedger.sol";
import {Clans} from "./Clans.sol";
import {IVillages} from "./interfaces/IVillages.sol";

/// @notice Deterministic armies, asynchronous movement, champion and camp engine.
/// @dev State is scoped by the calling game. Only resolve/completeTraining accept an explicit game,
/// and those can only execute actions already authorized through that game's player entry point.
contract Army is Guard {
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant MAX_SUPPORT = 30;
    uint256 public constant MAX_XP = 1_000_000_000_000;
    GameRules public immutable rules;
    SeedLedger public immutable ledger;
    Clans public immutable clans;
    uint256 public immutable seasonStartedAt;

    struct Champion {
        uint256 xp;
        uint8 might;
        uint8 attack;
        uint8 defense;
        uint8 carry;
        bool away;
    }

    struct Training {
        uint8 kind;
        uint32 count;
        uint64 readyAt;
    }

    struct Movement {
        address owner;
        address target;
        uint16 campId;
        uint8 mode; // 1 raid, 2 scout, 3 support outbound, 4 return, 5 stationed, 6 completed
        bool champion;
        uint64 arriveAt;
        uint64 travelTime;
        uint32[7] units;
        uint256[4] loot;
    }

    struct Report {
        uint64 resolvedAt;
        uint256 attack;
        uint256 defense;
        uint256 attackerLostValue;
        uint256 defenderLostValue;
        uint256[4] loot;
        bool decisive;
        bool cancelled;
    }

    struct Camp {
        bool initialized;
        uint64 regrowAt;
        uint64 lastStock;
        uint256 defense;
        uint256[4] stock;
    }

    struct World {
        uint256 nextMovement;
        mapping(address => uint32[7]) home;
        mapping(address => uint256) room;
        mapping(address => Training) training;
        mapping(address => Champion) champions;
        mapping(uint256 => Movement) movements;
        mapping(uint256 => Report) reports;
        mapping(address => uint256[]) support;
        mapping(address => mapping(address => uint256)) supporting;
        mapping(bytes32 => uint8) raids;
        mapping(address => mapping(address => uint64)) scoutedUntil;
        mapping(uint16 => Camp) camps;
    }

    struct Combat {
        uint256 attack;
        uint256 defense;
        uint256 attackerLost;
        uint256 defenderLost;
        bool decisive;
        bool weakTarget;
        G.Context attacking;
        G.Context defending;
    }
    mapping(address => World) private worlds;

    event TrainingOrdered(
        address indexed game, address indexed player, uint8 kind, uint256 count, uint256 readyAt
    );
    event TrainingCompleted(address indexed game, address indexed player, uint8 kind, uint256 count);
    event MovementSent(
        address indexed game,
        uint256 indexed id,
        address indexed owner,
        address target,
        uint16 campId,
        uint8 mode,
        uint256 arriveAt
    );
    event MovementResolved(address indexed game, uint256 indexed id, uint8 mode, uint256 nextArrival);
    event Battle(
        address indexed game,
        uint256 indexed id,
        uint256 attack,
        uint256 defense,
        uint256 attackerLost,
        uint256 defenderLost,
        bool decisive
    );
    event ChampionXP(address indexed game, address indexed player, uint256 added, uint256 total);
    event ChampionAllocated(
        address indexed game, address indexed player, uint8 might, uint8 attack, uint8 defense, uint8 carry
    );
    event Scouted(
        address indexed game, address indexed player, address indexed target, bool success, uint256 until
    );

    constructor(GameRules rules_, SeedLedger ledger_, Clans clans_) {
        require(
            address(rules_) != address(0) && address(ledger_) != address(0) && address(clans_) != address(0),
            E.InvalidDependency()
        );
        rules = rules_;
        ledger = ledger_;
        clans = clans_;
        seasonStartedAt = block.timestamp;
    }

    function home(address game, address who) external view returns (uint32[7] memory) {
        return worlds[game].home[who];
    }

    function allocatedRoom(address game, address who) external view returns (uint256) {
        return worlds[game].room[who];
    }

    function training(address game, address who) external view returns (Training memory) {
        return worlds[game].training[who];
    }

    function champion(address game, address who) external view returns (Champion memory) {
        return worlds[game].champions[who];
    }

    function movement(address game, uint256 id) external view returns (Movement memory) {
        return worlds[game].movements[id];
    }

    function report(address game, uint256 id) external view returns (Report memory) {
        return worlds[game].reports[id];
    }

    function movementCount(address game) external view returns (uint256) {
        return worlds[game].nextMovement;
    }

    function supportMovements(address game, address target) external view returns (uint256[] memory) {
        return worlds[game].support[target];
    }

    function scoutedUntil(address game, address who, address target) external view returns (uint64) {
        return worlds[game].scoutedUntil[who][target];
    }

    function camp(address game, uint16 id) external view returns (Camp memory) {
        require(id < 200, E.InvalidCamp());
        return worlds[game].camps[id];
    }

    function championLevel(address game, address who) public view returns (uint256) {
        return G.min(30, 1 + G.sqrt(worlds[game].champions[who].xp / 100));
    }

    function train(address who, uint8 kind, uint32 count) external nonReentrant {
        World storage w = worlds[msg.sender];
        G.Context memory c = _context(msg.sender, who);
        require(c.exists && w.training[who].readyAt == 0, E.TrainingBusyOrMissingVillage());
        (uint256[4] memory cost, uint256 duration, uint256 room) = abi.decode(
            ModuleCalls.read(
                address(rules), abi.encodeCall(rules.unitQuote, (kind, c.barracks, c.research, count)), 192
            ),
            (uint256[4], uint256, uint256)
        );
        require(w.room[who] + room <= c.room, E.InsufficientBurrowRoom());
        ModuleCalls.invoke(
            address(IVillages(msg.sender)), abi.encodeCall(IVillages(msg.sender).armySpend, (who, cost)), 0
        );
        w.room[who] += room;
        w.training[who] = Training(kind, count, uint64(block.timestamp + duration));
        emit TrainingOrdered(msg.sender, who, kind, count, block.timestamp + duration);
    }

    function completeTraining(address game, address who) external nonReentrant {
        World storage w = worlds[game];
        Training memory t = w.training[who];
        require(t.readyAt != 0 && block.timestamp >= t.readyAt, E.TrainingNotReady());
        delete w.training[who];
        w.home[who][t.kind] += t.count;
        emit TrainingCompleted(game, who, t.kind, t.count);
    }

    function creditXP(address who, uint256 amount) external nonReentrant {
        _xp(msg.sender, who, amount);
    }

    function _xp(address game, address who, uint256 amount) private {
        if (amount == 0) return;
        if (
            abi.decode(
                    ModuleCalls.read(address(ledger), abi.encodeCall(ledger.nftBalance, (who)), 32), (uint256)
                ) != 0
        ) amount = amount * 110 / 100;
        Champion storage c = worlds[game].champions[who];
        c.xp = G.min(MAX_XP, c.xp + amount);
        emit ChampionXP(game, who, amount, c.xp);
    }

    function allocate(address who, uint8 might, uint8 attack, uint8 defense, uint8 carry) external {
        Champion storage c = worlds[msg.sender].champions[who];
        require(attack <= 20 && defense <= 20 && carry <= 20, E.StatCap());
        require(
            might >= c.might && attack >= c.attack && defense >= c.defense && carry >= c.carry,
            E.PointsCannotBeReassigned()
        );
        require(
            uint256(might) + attack + defense + carry <= 4 * (championLevel(msg.sender, who) - 1),
            E.InsufficientChampionPoints()
        );
        c.might = might;
        c.attack = attack;
        c.defense = defense;
        c.carry = carry;
        emit ChampionAllocated(msg.sender, who, might, attack, defense, carry);
    }

    function championStats(address game, address who)
        public
        view
        returns (uint256 might, uint256 attackBonus, uint256 defenseBonus, uint256 carryBonus)
    {
        Champion storage c = worlds[game].champions[who];
        might = 50 + uint256(c.might) * 25;
        attackBonus = uint256(c.attack) * 5000;
        defenseBonus = uint256(c.defense) * 5000;
        carryBonus = uint256(c.carry) * 10000;
        if (
            abi.decode(
                    ModuleCalls.read(address(ledger), abi.encodeCall(ledger.nftBalance, (who)), 32), (uint256)
                ) != 0
        ) {
            might = might * 110 / 100;
            attackBonus = attackBonus * 110 / 100;
            defenseBonus = defenseBonus * 110 / 100;
            carryBonus = carryBonus * 110 / 100;
        }
    }

    function travelTime(uint16 from, uint16 to, uint256 speed) public pure returns (uint256) {
        require(from < 10000 && to < 10000 && speed > 0 && speed <= 100, E.InvalidTravel());
        uint256 dx = from % 100 > to % 100 ? from % 100 - to % 100 : to % 100 - from % 100;
        uint256 dy = from / 100 > to / 100 ? from / 100 - to / 100 : to / 100 - from / 100;
        uint256 squared = (dx * dx + dy * dy) * UNIT * UNIT;
        uint256 distance = G.sqrt(squared);
        if (distance * distance < squared) ++distance;
        return G.ceilDiv(G.min(type(uint64).max, distance == 0 ? UNIT : distance) * 3600, speed * UNIT);
    }

    function _raidKey(address who, address target, uint16 campId, uint256 day, bool arrival)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(who, target, target == address(0) ? campId : 0, day, arrival));
    }

    function send(
        address who,
        address target,
        uint16 campId,
        uint32[7] calldata units,
        bool withChampion,
        uint8 mode
    ) external nonReentrant returns (uint256 id) {
        require(mode >= 1 && mode <= 3 && who != target, E.InvalidMovement());
        World storage w = worlds[msg.sender];
        G.Context memory c = _context(msg.sender, who);
        require(c.exists, E.MissingVillage());
        uint16 destination;
        if (target == address(0)) {
            require(campId < 200 && mode == 1, E.InvalidCampMovement());
            destination = G.tile(uint256(campId) * 50 + 49);
        } else {
            G.Context memory d = _context(msg.sender, target);
            require(d.exists, E.MissingTarget());
            destination = d.tile;
            bool allied = _sameClan(msg.sender, who, target);
            if (mode == 3) {
                require(allied && !withChampion && w.supporting[who][target] == 0, E.InvalidSupport());
            } else {
                require(!allied && block.timestamp >= d.shieldUntil, E.TargetProtected());
            }
        }
        if (mode == 1) {
            bytes32 key = _raidKey(
                who,
                target,
                campId,
                abi.decode(
                    ModuleCalls.read(address(ledger), abi.encodeCall(ledger.currentDay, ()), 32), (uint256)
                ),
                false
            );
            require(w.raids[key] < 3, E.DailyRaidLimit());
            ++w.raids[key];
        }
        uint256 speed = type(uint256).max;
        uint256 count;
        for (uint8 i; i < 7; ++i) {
            require(units[i] <= w.home[who][i], E.InsufficientTroops());
            if (mode == 2 && i != 6) require(units[i] == 0, E.OnlyScoutsReconnoitre());
            if (units[i] != 0) {
                (,, uint256 s,,,) = _unitStats(i);
                speed = G.min(speed, s);
                count += units[i];
            }
            w.home[who][i] -= units[i];
        }
        require(
            count > 0
                && count
                    <= abi.decode(
                        ModuleCalls.read(address(rules), abi.encodeCall(rules.MAX_TROOPS, ()), 32), (uint256)
                    ),
            E.InvalidTroopCount()
        );
        if (mode == 2) require(!withChampion, E.ScoutsTravelAlone());
        if (withChampion) {
            require(!w.champions[who].away, E.ChampionAway());
            w.champions[who].away = true;
        }
        uint256 duration = travelTime(c.tile, destination, speed);
        if (c.research >= 5) duration = G.ceilDiv(duration * 100, 120);
        id = ++w.nextMovement;
        Movement storage m = w.movements[id];
        m.owner = who;
        m.target = target;
        m.campId = campId;
        m.mode = mode;
        m.champion = withChampion;
        m.arriveAt = uint64(block.timestamp + duration);
        m.travelTime = uint64(duration);
        m.units = units;
        if (mode == 3) w.supporting[who][target] = id;
        emit MovementSent(msg.sender, id, who, target, campId, mode, block.timestamp + duration);
    }

    function resolve(address game, uint256 id) external nonReentrant {
        World storage w = worlds[game];
        Movement storage m = w.movements[id];
        require(m.mode >= 1 && m.mode <= 4 && block.timestamp >= m.arriveAt, E.MovementNotArrived());
        if (m.mode == 4) {
            ModuleCalls.invoke(
                address(IVillages(game)), abi.encodeCall(IVillages(game).armyCredit, (m.owner, m.loot)), 0
            );
            for (uint8 i; i < 7; ++i) {
                w.home[m.owner][i] += m.units[i];
            }
            if (m.champion) w.champions[m.owner].away = false;
            delete m.loot;
            delete m.units;
            m.mode = 6;
        } else if (m.mode == 3) {
            if (_sameClan(game, m.owner, m.target) && w.support[m.target].length < MAX_SUPPORT) {
                m.mode = 5;
                w.support[m.target].push(id);
            } else {
                w.supporting[m.owner][m.target] = 0;
                _return(m);
            }
        } else {
            bool protected_;
            if (m.target != address(0)) {
                G.Context memory d = _context(game, m.target);
                protected_ = block.timestamp < d.shieldUntil || _sameClan(game, m.owner, m.target);
            }
            if (m.mode == 1) {
                bytes32 key = _raidKey(
                    m.owner,
                    m.target,
                    m.campId,
                    abi.decode(
                        ModuleCalls.read(address(ledger), abi.encodeCall(ledger.currentDay, ()), 32),
                        (uint256)
                    ),
                    true
                );
                if (w.raids[key] >= 3) protected_ = true;
                if (!protected_) ++w.raids[key];
            }
            if (protected_) {
                w.reports[id].cancelled = true;
                w.reports[id].resolvedAt = uint64(block.timestamp);
            } else if (m.mode == 2) {
                _scout(game, m);
            } else {
                _battle(game, id);
            }
            _return(m);
        }
        emit MovementResolved(game, id, m.mode, m.arriveAt);
    }

    function _return(Movement storage m) private {
        m.mode = 4;
        m.arriveAt = uint64(block.timestamp + m.travelTime);
    }

    function recall(address who, uint256 id) external nonReentrant {
        World storage w = worlds[msg.sender];
        Movement storage m = w.movements[id];
        require(m.mode == 5 && (who == m.owner || who == m.target), E.CannotRecallSupport());
        _recall(w, m, msg.sender, id);
    }

    /// @notice Anyone can return support whose owners have ceased to be clanmates.
    function returnFormerSupport(address game, uint256 id) external nonReentrant {
        World storage w = worlds[game];
        Movement storage m = w.movements[id];
        require(m.mode == 5 && !_sameClan(game, m.owner, m.target), E.SupportStillAllied());
        _recall(w, m, game, id);
    }

    function _recall(World storage w, Movement storage m, address game, uint256 id) private {
        _removeSupport(w, m.target, id);
        w.supporting[m.owner][m.target] = 0;
        _return(m);
        emit MovementResolved(game, id, m.mode, m.arriveAt);
    }

    function _removeSupport(World storage w, address target, uint256 id) private {
        uint256[] storage list = w.support[target];
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == id) {
                list[i] = list[list.length - 1];
                list.pop();
                return;
            }
        }
        revert E.MissingSupport();
    }

    function _scout(address game, Movement storage m) private {
        World storage w = worlds[game];
        ModuleCalls.invoke(address(IVillages(game)), abi.encodeCall(IVillages(game).armyTouch, (m.owner)), 0);
        uint256 enemy = w.home[m.target][6];
        uint256 lost = G.min(m.units[6], enemy);
        m.units[6] -= uint32(lost);
        w.room[m.owner] -= lost;
        bool success = m.units[6] != 0;
        if (success) w.scoutedUntil[m.owner][m.target] = uint64(block.timestamp + 12 hours);
        emit Scouted(game, m.owner, m.target, success, w.scoutedUntil[m.owner][m.target]);
    }

    function _strength(uint32[7] memory units, bool attacking) private view returns (uint256 total) {
        for (uint8 i; i < 7; ++i) {
            (uint256 a, uint256 d,,,,) = _unitStats(i);
            total += units[i] * (attacking ? a : d);
        }
    }

    function _attack(address game, Movement storage m, G.Context memory c)
        private
        view
        returns (uint256 power)
    {
        power = _strength(m.units, true) * (100 + uint256(c.forge) * 2) / 100;
        if (m.champion) {
            (uint256 might, uint256 bonus,,) = championStats(game, m.owner);
            power = power * (UNIT + bonus) / UNIT + might;
        }
        if (m.target != address(0) && worlds[game].scoutedUntil[m.owner][m.target] > block.timestamp) {
            power = power * 110 / 100;
        }
    }

    function _defense(address game, address who, G.Context memory c) private view returns (uint256 power) {
        World storage w = worlds[game];
        power = _strength(w.home[who], false) * (100 + uint256(c.forge) * 2) / 100;
        uint256[] storage list = w.support[who];
        for (uint256 i; i < list.length; ++i) {
            Movement storage s = w.movements[list[i]];
            if (_sameClan(game, s.owner, who)) {
                G.Context memory ally = _context(game, s.owner);
                power += _strength(s.units, false) * (100 + uint256(ally.forge) * 2) / 100;
            }
        }
        if (!w.champions[who].away) {
            (uint256 might,, uint256 bonus,) = championStats(game, who);
            power = (power + might) * (UNIT + bonus) / UNIT;
        }
        power = power * (100 + uint256(c.walls) * 4) / 100 + uint256(c.townHall) * 40;
    }

    function _losses(
        address game,
        address who,
        uint32[7] storage units,
        uint256 enemy,
        uint256 own,
        bool wipe,
        bool medicine
    ) private returns (uint256 killed) {
        ModuleCalls.invoke(address(IVillages(game)), abi.encodeCall(IVillages(game).armyTouch, (who)), 0);
        uint256 lostRoom;
        uint256[7] memory losses = wipe || own == 0 ? _all(units) : _casualties(units, enemy, own);
        for (uint8 i; i < 7; ++i) {
            uint256 lost = losses[i];
            if (medicine && !wipe) lost -= lost / 10;
            if (lost != 0) {
                units[i] -= uint32(lost);
                killed += lost
                    * abi.decode(
                        ModuleCalls.read(address(rules), abi.encodeCall(rules.unitValue, (i)), 32), (uint256)
                    );
                (,,,, uint256 room,) = _unitStats(i);
                lostRoom += lost * room;
            }
        }
        worlds[game].room[who] -= lostRoom;
    }

    function _all(uint32[7] memory units) private pure returns (uint256[7] memory losses) {
        for (uint8 i; i < 7; ++i) {
            losses[i] = units[i];
        }
    }

    /// @dev Rounds the army's casualties up once, not per stack: each stack loses its floored share of
    /// min(1, enemy / (2 * own)) and the aggregate remainder goes, one unit each, to the stacks with the
    /// largest fractional parts.
    function _casualties(uint32[7] memory units, uint256 enemy, uint256 own)
        private
        pure
        returns (uint256[7] memory losses)
    {
        uint256 denominator = own * 2;
        uint256[7] memory remainder;
        uint256 total;
        uint256 floored;
        for (uint8 i; i < 7; ++i) {
            uint256 share = uint256(units[i]) * enemy;
            if (share >= uint256(units[i]) * denominator) {
                losses[i] = units[i];
            } else {
                losses[i] = share / denominator;
                remainder[i] = share % denominator;
            }
            total += units[i];
            floored += losses[i];
        }
        uint256 extra = G.min(total, G.ceilDiv(total * enemy, denominator)) - floored;
        for (; extra != 0; --extra) {
            uint8 best = 7;
            for (uint8 i; i < 7; ++i) {
                if (remainder[i] != 0 && (best == 7 || remainder[i] > remainder[best])) best = i;
            }
            if (best == 7) break;
            ++losses[best];
            remainder[best] = 0;
        }
    }

    function _carry(address game, Movement storage m, uint8 tier) private view returns (uint256 capacity) {
        for (uint8 i; i < 7; ++i) {
            (,,, uint256 carry,,) = _unitStats(i);
            capacity += m.units[i] * carry;
        }
        uint256 bonus = tier >= 5 ? 400_000 : tier >= 3 ? 200_000 : 0;
        if (m.champion) {
            (,,, uint256 championCarry) = championStats(game, m.owner);
            bonus += championCarry;
        }
        return capacity * UNIT * (UNIT + bonus) / UNIT;
    }

    function _battle(address game, uint256 id) private {
        World storage w = worlds[game];
        Movement storage m = w.movements[id];
        Combat memory c;
        c.attacking = _context(game, m.owner);
        c.attack = _attack(game, m, c.attacking);
        if (m.target == address(0)) {
            _refreshCamp(w.camps[m.campId], m.campId);
            c.defense = w.camps[m.campId].defense;
        } else {
            c.defending = _context(game, m.target);
            c.defense = _defense(game, m.target, c.defending);
            c.weakTarget = uint256(c.defending.townHall) + 3 <= c.attacking.townHall;
        }
        c.decisive = c.attack != 0 && c.attack >= 2 * c.defense;
        c.attackerLost =
            _losses(game, m.owner, m.units, c.defense, c.attack, false, c.attacking.research >= 4);
        if (m.target == address(0)) {
            Camp storage camp_ = w.camps[m.campId];
            uint256 damage = c.decisive ? camp_.defense : G.min(camp_.defense, c.attack / 2);
            camp_.defense -= damage;
            // Repeated raids on an empty camp must not postpone its existing regrowth.
            if (damage != 0 && camp_.regrowAt == 0) camp_.regrowAt = uint64(block.timestamp + 24 hours);
            // Camp garrison's 60/40 shield/spear mix: average defense 56, average cost 204.
            c.defenderLost = damage * 204 / 56;
            if (c.decisive) {
                uint256 carry = _carry(game, m, c.attacking.research) / 4;
                for (uint8 i; i < 4; ++i) {
                    m.loot[i] = G.min(carry, camp_.stock[i]);
                    camp_.stock[i] -= m.loot[i];
                }
            }
        } else {
            c.defenderLost = _losses(
                game, m.target, w.home[m.target], c.attack, c.defense, c.decisive, c.defending.research >= 4
            );
            uint256[] storage list = w.support[m.target];
            for (uint256 i; i < list.length; ++i) {
                Movement storage s = w.movements[list[i]];
                if (_sameClan(game, s.owner, m.target)) {
                    G.Context memory ally = _context(game, s.owner);
                    c.defenderLost += _losses(
                        game, s.owner, s.units, c.attack, c.defense, c.decisive, ally.research >= 4
                    );
                }
            }
            // Losses above use the original defense and order for every contingent. Only afterwards
            // release emptied slots/pairs; walk backwards so swap-and-pop cannot skip an entry.
            for (uint256 i = list.length; i != 0; --i) {
                uint256 supportId = list[i - 1];
                Movement storage s = w.movements[supportId];
                uint32 remaining;
                for (uint8 j; j < 7; ++j) {
                    remaining |= s.units[j];
                }
                if (remaining == 0) {
                    _recall(w, s, game, supportId);
                }
            }
            if (c.decisive) {
                uint256 carry = _carry(game, m, c.attacking.research);
                if (c.weakTarget) carry /= 2;
                m.loot = abi.decode(
                    ModuleCalls.invoke(
                        address(IVillages(game)),
                        abi.encodeCall(IVillages(game).armyLoot, (m.target, carry)),
                        128
                    ),
                    (uint256[4])
                );
                uint256 damage = G.min(2, uint256(m.units[5]) / 20);
                if (damage != 0) {
                    ModuleCalls.invoke(
                        address(IVillages(game)),
                        abi.encodeCall(IVillages(game).armyDamageWalls, (m.target, uint8(damage))),
                        0
                    );
                }
            }
            if (!c.weakTarget) {
                ModuleCalls.invoke(
                    address(IVillages(game)),
                    abi.encodeCall(IVillages(game).armyRecord, (m.target, 3, c.attackerLost)),
                    0
                );
                _xp(game, m.target, c.attackerLost / 20);
            }
        }
        if (!c.weakTarget) {
            ModuleCalls.invoke(
                address(IVillages(game)),
                abi.encodeCall(IVillages(game).armyRecord, (m.owner, 2, c.defenderLost)),
                0
            );
            _xp(game, m.owner, c.defenderLost / 20);
        }
        uint256 totalLoot = m.loot[0] + m.loot[1] + m.loot[2] + m.loot[3];
        if (totalLoot != 0) {
            ModuleCalls.invoke(
                address(IVillages(game)),
                abi.encodeCall(IVillages(game).armyRecord, (m.owner, 4, totalLoot)),
                0
            );
        }
        Report storage result = w.reports[id];
        result.resolvedAt = uint64(block.timestamp);
        result.attack = c.attack;
        result.defense = c.defense;
        result.attackerLostValue = c.attackerLost;
        result.defenderLostValue = c.defenderLost;
        result.loot = m.loot;
        result.decisive = c.decisive;
        result.cancelled = false;
        emit Battle(game, id, c.attack, c.defense, c.attackerLost, c.defenderLost, c.decisive);
    }

    function _campDay() private view returns (uint256) {
        return abi.decode(
            ModuleCalls.read(address(ledger), abi.encodeCall(ledger.currentDay, ()), 32), (uint256)
        )
            - abi.decode(
            ModuleCalls.read(address(ledger), abi.encodeCall(ledger.dayAt, (seasonStartedAt)), 32), (uint256)
        );
    }

    function campParameters(uint16 id) public view returns (uint256 defense, uint256 hourlyStock) {
        require(id < 200, E.InvalidCamp());
        uint256 size = ((uint256(0x96643c) >> (8 * uint256(id % 3))) & 255);
        uint256 day = _campDay();
        defense = G.min(4000, 150 + 40 * day) * size / 100;
        hourlyStock = (20 + 2 * day) * UNIT * size / 100;
    }

    /// @dev Integral of the daily stepwise camp rate, anchored to the 04:00 UTC season day.
    function _campIntegral(uint16 id, uint256 timestamp) private view returns (uint256) {
        uint256 epoch = abi.decode(
                ModuleCalls.read(address(ledger), abi.encodeCall(ledger.dayAt, (seasonStartedAt)), 32),
                (uint256)
            ) * 1 days + 4 hours;
        uint256 elapsed = timestamp >= epoch ? timestamp - epoch : 0;
        uint256 days_ = elapsed / 1 days;
        uint256 weightedSeconds =
            (days_ * days_ + 19 * days_) * 1 days + (20 + 2 * days_) * (elapsed % 1 days);
        return weightedSeconds * UNIT * ((uint256(0x96643c) >> (8 * uint256(id % 3))) & 255) / 100 / 3600;
    }

    function _refreshCamp(Camp storage c, uint16 id) private {
        (uint256 defense, uint256 rate) = campParameters(id);
        if (!c.initialized) {
            c.initialized = true;
            c.lastStock = uint64(seasonStartedAt);
            c.defense = defense;
        }
        if (c.regrowAt != 0 && block.timestamp >= c.regrowAt) {
            c.defense = defense;
            c.regrowAt = 0;
        }
        uint256 produced = _campIntegral(id, block.timestamp) - _campIntegral(id, c.lastStock);
        for (uint8 i; i < 4; ++i) {
            c.stock[i] = G.min(rate * 24, c.stock[i] + produced);
        }
        c.lastStock = uint64(block.timestamp);
    }

    function _context(address game, address who) private view returns (G.Context memory) {
        return abi.decode(
            ModuleCalls.read(game, abi.encodeCall(IVillages(game).armyContext, (who)), 288), (G.Context)
        );
    }

    function _sameClan(address game, address a, address b) private view returns (bool) {
        return abi.decode(
            ModuleCalls.read(address(clans), abi.encodeCall(clans.sameClan, (game, a, b)), 32), (bool)
        );
    }

    function _unitStats(uint8 kind)
        private
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return abi.decode(
            ModuleCalls.read(address(rules), abi.encodeCall(rules.unitStats, (kind)), 192),
            (uint256, uint256, uint256, uint256, uint256, uint256)
        );
    }
}
