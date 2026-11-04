// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GameErrors as E} from "./libraries/GameErrors.sol";

import {ISqueekCore, ISqueekNFT} from "./interfaces/ISqueek.sol";
import {GameTypes as G} from "./libraries/GameTypes.sol";
import {Guard} from "./libraries/Guard.sol";

/// @notice Daily work checkpoints and nontransferable, caller-scoped village balances.
/// @dev The canonical game namespace is the deployed Villages contract. No approvals or transfers exist.
contract SeedLedger is Guard {
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant REPOINT_DELAY = 72 hours;
    uint256 public constant CORE_READ_GAS = 200_000;
    uint256 public constant NFT_READ_GAS = 100_000;
    address public owner;
    address public core;
    address public squeek;
    address public pendingCore;
    address public pendingSqueek;
    uint64 public repointAfter;
    uint64 public lastCumulativeWork;

    struct Observation {
        uint64 timestamp;
        uint64 day;
        uint64 work;
        uint256 seedIndex;
        uint256 xpIndex;
        uint256[11] wheelIntegral;
    }

    struct Account {
        bool exists;
        uint256 cursor;
        uint256 balance;
    }
    Observation[] private observations;
    mapping(address game => mapping(address player => Account)) private accounts;
    mapping(address game => uint256) public minted;
    mapping(address game => uint256) public burned;

    error Unauthorized();
    error InvalidAddress();
    error AlreadyCheckpointed();
    error WorkDecreased();
    error ExternalReadFailed();
    error NoClaim();
    error InsufficientSeed();
    error TimelockPending();

    event Checkpoint(uint256 indexed index, uint256 indexed day, uint256 work, uint256 cumulativeWork);
    event Registered(address indexed game, address indexed player);
    event Claimed(
        address indexed game, address indexed player, uint256 throughIndex, uint256 seed, uint256 xp
    );
    event Burned(address indexed game, address indexed player, uint256 amount);
    event Refunded(address indexed game, address indexed player, uint256 amount);
    event RepointProposed(address core, address squeek, uint256 executableAt);
    event RepointApplied(address core, address squeek);
    event RepointCancelled();
    event OwnershipRenounced();

    constructor(address owner_, address core_, address squeek_) {
        if (owner_ == address(0) || core_ == address(0) || squeek_ == address(0)) revert InvalidAddress();
        owner = owner_;
        core = core_;
        squeek = squeek_;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function dayAt(uint256 timestamp) public pure returns (uint256) {
        return timestamp < 4 hours ? 0 : (timestamp - 4 hours) / 1 days;
    }

    function currentDay() public view returns (uint256) {
        return dayAt(block.timestamp);
    }

    function observationCount() external view returns (uint256) {
        return observations.length;
    }

    function observation(uint256 index) external view returns (Observation memory) {
        return observations[index];
    }

    function balanceOf(address game, address player) external view returns (uint256) {
        return accounts[game][player].balance;
    }

    function account(address game, address player) external view returns (Account memory) {
        return accounts[game][player];
    }

    function lastWork() public view returns (uint256) {
        return observations.length == 0 ? 0 : observations[observations.length - 1].work;
    }

    function _work(address source) private view returns (uint64) {
        (bool ok, bytes memory data) =
            source.staticcall{gas: CORE_READ_GAS}(abi.encodeCall(ISqueekCore.state, ()));
        if (!ok || data.length != 256) revert ExternalReadFailed();
        uint256[8] memory words = abi.decode(data, (uint256[8]));
        if (
            words[0] > type(uint64).max || words[1] > type(uint64).max || words[2] > type(uint96).max
                || words[3] > type(uint64).max || words[4] > type(uint96).max || words[5] > type(uint32).max
                || words[7] > 1
        ) revert ExternalReadFailed();
        return uint64(words[1]);
    }

    function nftBalance(address player) public view returns (uint256) {
        return _nftBalance(squeek, player);
    }

    function _nftBalance(address source, address player) private view returns (uint256) {
        (bool ok, bytes memory data) =
            source.staticcall{gas: NFT_READ_GAS}(abi.encodeCall(ISqueekNFT.balanceOf, (player)));
        if (!ok || data.length != 32) revert ExternalReadFailed();
        return abi.decode(data, (uint256));
    }

    /// @notice First checkpoint establishes a baseline; later ones reward the observed work delta.
    function checkpoint() external nonReentrant {
        _checkpoint();
    }

    function _checkpoint() private {
        uint256 length = observations.length;
        uint256 day = currentDay();
        if (length != 0 && observations[length - 1].day == day) revert AlreadyCheckpointed();
        uint64 current = _work(core);
        if (length != 0 && current < lastCumulativeWork) revert WorkDecreased();
        // No external calls follow: build the new observation directly in its storage slot.
        observations.push();
        Observation storage next = observations[length];
        next.timestamp = uint64(block.timestamp);
        next.day = uint64(day);
        if (length != 0) {
            Observation storage previous = observations[length - 1];
            next.work = current - lastCumulativeWork;
            next.seedIndex = previous.seedIndex + uint256(next.work) * UNIT / 10;
            next.xpIndex = previous.xpIndex + G.min(150, uint256(next.work) / 100);
            for (uint8 l = 1; l <= 10; ++l) {
                next.wheelIntegral[l] = previous.wheelIntegral[l] + _bonus(previous.work, l)
                    * (block.timestamp - previous.timestamp);
            }
        }
        lastCumulativeWork = current;
        emit Checkpoint(length, day, next.work, current);
    }

    function _bonus(uint256 work, uint8 level) private pure returns (uint256) {
        return G.min(work * UNIT / 4320, uint256(level) * UNIT / 4);
    }

    /// @notice Time integral of Wheelhouse's fractional output bonus at an arbitrary past time.
    function wheelIntegral(uint8 level, uint256 timestamp) external view returns (uint256) {
        require(level <= 10 && timestamp <= block.timestamp, E.InvalidIntegralQuery());
        uint256 length = observations.length;
        if (length == 0 || level == 0 || timestamp < observations[0].timestamp) return 0;
        uint256 lo;
        uint256 hi = length;
        while (lo + 1 < hi) {
            uint256 mid = (lo + hi) / 2;
            if (observations[mid].timestamp <= timestamp) lo = mid;
            else hi = mid;
        }
        Observation storage o = observations[lo];
        return o.wheelIntegral[level] + _bonus(o.work, level) * (timestamp - o.timestamp);
    }

    function register(address player) external nonReentrant {
        require(
            player != address(0) && !accounts[msg.sender][player].exists, E.AlreadyRegisteredOrInvalidPlayer()
        );
        if (observations.length == 0 || observations[observations.length - 1].day < currentDay()) {
            _checkpoint();
        }
        accounts[msg.sender][player] = Account(true, observations.length - 1, 1500 * UNIT);
        minted[msg.sender] += 1500 * UNIT;
        emit Registered(msg.sender, player);
    }

    function claim(address player) external nonReentrant returns (uint256 seed, uint256 xp) {
        Account storage a = accounts[msg.sender][player];
        uint256 latest = observations.length == 0 ? 0 : observations.length - 1;
        if (!a.exists || a.cursor == latest) revert NoClaim();
        seed = observations[latest].seedIndex - observations[a.cursor].seedIndex;
        xp = observations[latest].xpIndex - observations[a.cursor].xpIndex;
        a.cursor = latest;
        a.balance += seed;
        minted[msg.sender] += seed;
        emit Claimed(msg.sender, player, latest, seed, xp);
    }

    function burn(address player, uint256 amount) external {
        Account storage a = accounts[msg.sender][player];
        if (!a.exists || a.balance < amount) revert InsufficientSeed();
        a.balance -= amount;
        burned[msg.sender] += amount;
        emit Burned(msg.sender, player, amount);
    }

    /// @dev Only refunds previously burned SEED within the caller's own namespace.
    function refund(address player, uint256 amount) external {
        require(accounts[msg.sender][player].exists && amount <= burned[msg.sender], E.InvalidRefund());
        accounts[msg.sender][player].balance += amount;
        burned[msg.sender] -= amount;
        emit Refunded(msg.sender, player, amount);
    }

    function proposeRepoint(address core_, address squeek_) external onlyOwner {
        if (core_ == address(0) || squeek_ == address(0)) revert InvalidAddress();
        pendingCore = core_;
        pendingSqueek = squeek_;
        repointAfter = uint64(block.timestamp + REPOINT_DELAY);
        emit RepointProposed(core_, squeek_, repointAfter);
    }

    function cancelRepoint() external onlyOwner {
        _cancel();
        emit RepointCancelled();
    }

    function _cancel() private {
        pendingCore = address(0);
        pendingSqueek = address(0);
        repointAfter = 0;
    }

    function applyRepoint() external onlyOwner nonReentrant {
        if (repointAfter == 0 || block.timestamp < repointAfter) revert TimelockPending();
        // Rebaseline a replacement Core, preventing old or lower counters from creating rewards.
        // A repoint to the same Core also rebaselines a counter that went backwards, restoring checkpoints.
        uint64 current = _work(pendingCore);
        if (pendingCore != core || current < lastCumulativeWork) lastCumulativeWork = current;
        _nftBalance(pendingSqueek, owner);
        core = pendingCore;
        squeek = pendingSqueek;
        _cancel();
        emit RepointApplied(core, squeek);
    }

    function renounceOwnership() external onlyOwner {
        owner = address(0);
        _cancel();
        emit OwnershipRenounced();
    }
}
