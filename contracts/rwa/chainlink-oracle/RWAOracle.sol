// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// Minimal Chainlink AggregatorV3 interface. Not vendored from Chainlink's
/// full package because we only need this one interface — inlining it avoids
/// a whole new vendor tree.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/// @title RWAOracle
/// @notice Wraps one or more Chainlink AggregatorV3 feeds with staleness and
///         heartbeat enforcement. Downstream RWA contracts read prices
///         through this wrapper; if any safety check fails, the read reverts.
///
///         Managed feed registry — admin registers feeds under a bytes32
///         identifier (e.g. keccak256("USDC/USD"), keccak256("XAU/USD"),
///         keccak256("M_HELEN_HOTEL_NAV")).
contract RWAOracle is AccessControl {
    bytes32 public constant FEED_ADMIN_ROLE = keccak256("FEED_ADMIN_ROLE");

    struct Feed {
        AggregatorV3Interface aggregator;
        /// Max acceptable age of the latest answer in seconds.
        uint32 maxStalenessSec;
        /// Max acceptable gap since last update in seconds (heartbeat).
        uint32 maxHeartbeatSec;
        /// True once registered.
        bool exists;
    }

    mapping(bytes32 => Feed) public feeds;

    event FeedRegistered(bytes32 indexed feedId, address aggregator, uint32 maxStaleness, uint32 maxHeartbeat);
    event FeedRemoved(bytes32 indexed feedId);

    error FeedNotFound(bytes32 feedId);
    error AnswerStale(bytes32 feedId, uint256 answerAge, uint32 maxStaleness);
    error HeartbeatMissed(bytes32 feedId, uint256 lastUpdate, uint32 maxHeartbeat);
    error NegativeAnswer(bytes32 feedId, int256 answer);
    error IncompleteRound(bytes32 feedId, uint80 roundId, uint80 answeredInRound);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEED_ADMIN_ROLE, admin);
    }

    function registerFeed(
        bytes32 feedId,
        address aggregator,
        uint32 maxStalenessSec,
        uint32 maxHeartbeatSec
    ) external onlyRole(FEED_ADMIN_ROLE) {
        feeds[feedId] = Feed({
            aggregator: AggregatorV3Interface(aggregator),
            maxStalenessSec: maxStalenessSec,
            maxHeartbeatSec: maxHeartbeatSec,
            exists: true
        });
        emit FeedRegistered(feedId, aggregator, maxStalenessSec, maxHeartbeatSec);
    }

    function removeFeed(bytes32 feedId) external onlyRole(FEED_ADMIN_ROLE) {
        delete feeds[feedId];
        emit FeedRemoved(feedId);
    }

    /// @notice Read a price with all safety checks. Reverts with specific
    ///         reasons on any violation — no silent zero-returns.
    function priceFresh(bytes32 feedId) external view returns (
        int256 answer,
        uint8 decimals,
        uint256 updatedAt
    ) {
        Feed storage f = feeds[feedId];
        if (!f.exists) revert FeedNotFound(feedId);

        (uint80 roundId, int256 ans, , uint256 upd, uint80 answeredIn) = f.aggregator.latestRoundData();

        if (ans <= 0) revert NegativeAnswer(feedId, ans);
        if (answeredIn < roundId) revert IncompleteRound(feedId, roundId, answeredIn);

        uint256 age = block.timestamp - upd;
        if (age > f.maxStalenessSec) revert AnswerStale(feedId, age, f.maxStalenessSec);
        if (age > f.maxHeartbeatSec) revert HeartbeatMissed(feedId, upd, f.maxHeartbeatSec);

        return (ans, f.aggregator.decimals(), upd);
    }

    /// @notice Read without staleness checks — for read-only UI display where
    ///         a stale answer is acceptable (with an "as of" annotation).
    ///         RWA contracts that MOVE FUNDS must use priceFresh().
    function priceRaw(bytes32 feedId) external view returns (
        int256 answer,
        uint8 decimals,
        uint256 updatedAt
    ) {
        Feed storage f = feeds[feedId];
        if (!f.exists) revert FeedNotFound(feedId);
        (, int256 ans, , uint256 upd, ) = f.aggregator.latestRoundData();
        return (ans, f.aggregator.decimals(), upd);
    }
}
