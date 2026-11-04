// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameErrors as E} from "./libraries/GameErrors.sol";

import {GameTypes as G} from "./libraries/GameTypes.sol";

/// @notice Caller-scoped clans and season/week counters; canonical caller is Villages.
contract Clans {
    uint256 public immutable seasonStartedAt;
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant MAX_MEMBERS = 30;

    struct Clan {
        string name;
        address founder;
        uint8 capacity;
        address[] members;
    }

    struct Counters {
        uint256 build;
        uint256 research;
        uint256 attack;
        uint256 defense;
        uint256 loot;
    }

    struct World {
        uint256 nextClan;
        mapping(uint256 => Clan) clans;
        mapping(address => uint256) membership;
        mapping(bytes32 => bool) names;
        mapping(address => Counters) season;
        mapping(uint256 => mapping(address => Counters)) weeklyCounters;
        mapping(uint256 => mapping(address => bool)) invited;
    }
    mapping(address => World) private worlds;
    event ClanFounded(address indexed game, uint256 indexed clanId, address indexed founder, string name);
    event Joined(address indexed game, uint256 indexed clanId, address indexed player);
    event Invited(address indexed game, uint256 indexed clanId, address indexed player, bool open);
    event Left(address indexed game, uint256 indexed clanId, address indexed player);
    event CapacityRaised(address indexed game, uint256 indexed clanId, uint256 capacity);
    event Ranked(
        address indexed game, address indexed player, uint256 indexed week, uint8 category, uint256 amount
    );

    constructor() {
        seasonStartedAt = block.timestamp;
    }

    function week() public view returns (uint256) {
        return (block.timestamp - seasonStartedAt) / 7 days;
    }

    function clanOf(address game, address player) external view returns (uint256) {
        return worlds[game].membership[player];
    }

    function sameClan(address game, address a, address b) public view returns (bool) {
        uint256 id = worlds[game].membership[a];
        return id != 0 && id == worlds[game].membership[b];
    }

    function invited(address game, uint256 id, address player) external view returns (bool) {
        return worlds[game].invited[id][player];
    }

    function clan(address game, uint256 id) external view returns (Clan memory) {
        return worlds[game].clans[id];
    }

    function counters(address game, address player, bool weekly, uint256 week_)
        external
        view
        returns (Counters memory)
    {
        return weekly ? worlds[game].weeklyCounters[week_][player] : worlds[game].season[player];
    }

    function overall(address game, address player, bool weekly, uint256 week_)
        external
        view
        returns (uint256)
    {
        Counters storage c = weekly ? worlds[game].weeklyCounters[week_][player] : worlds[game].season[player];
        uint256 build = c.build / (100 * UNIT);
        return build + c.research / (100 * UNIT) + G.min(build, (c.attack + c.defense) / 200);
    }

    function found(address player, string calldata name, uint8 hall) external returns (uint256 id) {
        require(hall >= 3 && hall <= 10, E.ClanHall3Required());
        World storage w = worlds[msg.sender];
        require(w.membership[player] == 0 && player != address(0), E.AlreadyInClan());
        bytes32 key = G.nameKey(name, 24);
        require(!w.names[key], E.ClanNameTaken());
        w.names[key] = true;
        id = ++w.nextClan;
        Clan storage c = w.clans[id];
        c.name = name;
        c.founder = player;
        c.capacity = hall * 3;
        c.members.push(player);
        w.membership[player] = id;
        emit ClanFounded(msg.sender, id, player, name);
    }

    function join(address player, uint256 id, uint8 hall) external {
        World storage w = worlds[msg.sender];
        Clan storage c = w.clans[id];
        require(hall >= 1 && player != address(0) && w.membership[player] == 0, E.CannotJoin());
        require(c.founder != address(0) && c.members.length < c.capacity, E.ClanFullOrMissing());
        require(w.invited[id][player], E.NotInvited());
        delete w.invited[id][player];
        w.membership[player] = id;
        c.members.push(player);
        emit Joined(msg.sender, id, player);
    }

    /// @notice Only the founder admits members; an invitation is consumed by joining.
    function invite(address founder, address player, bool open) external {
        World storage w = worlds[msg.sender];
        uint256 id = w.membership[founder];
        require(id != 0 && w.clans[id].founder == founder && player != address(0), E.OnlyFounderInvites());
        w.invited[id][player] = open;
        emit Invited(msg.sender, id, player, open);
    }

    function leave(address player) external {
        World storage w = worlds[msg.sender];
        uint256 id = w.membership[player];
        Clan storage c = w.clans[id];
        require(id != 0, E.NotInClan());
        require(c.founder != player || c.members.length == 1, E.FounderLeavesLast());
        for (uint256 i; i < c.members.length; ++i) {
            if (c.members[i] == player) {
                c.members[i] = c.members[c.members.length - 1];
                c.members.pop();
                break;
            }
        }
        delete w.membership[player];
        if (c.members.length == 0) c.founder = address(0);
        emit Left(msg.sender, id, player);
    }

    function raiseCapacity(address player, uint8 hall) external {
        World storage w = worlds[msg.sender];
        uint256 id = w.membership[player];
        Clan storage c = w.clans[id];
        require(
            id != 0 && c.founder == player && hall <= 10 && hall * 3 > c.capacity, E.CannotRaiseCapacity()
        );
        c.capacity = hall * 3;
        emit CapacityRaised(msg.sender, id, c.capacity);
    }

    function record(address player, uint8 kind, uint256 amount) external {
        require(kind < 5, E.InvalidCounter());
        _add(worlds[msg.sender].season[player], kind, amount);
        uint256 week_ = week();
        _add(worlds[msg.sender].weeklyCounters[week_][player], kind, amount);
        emit Ranked(msg.sender, player, week_, kind, amount);
    }

    function _add(Counters storage c, uint8 kind, uint256 amount) private {
        if (kind == 0) c.build += amount;
        else if (kind == 1) c.research += amount;
        else if (kind == 2) c.attack += amount;
        else if (kind == 3) c.defense += amount;
        else c.loot += amount;
    }
}
