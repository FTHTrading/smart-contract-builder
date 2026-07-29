// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// Minimal AggregatorV3 interface — same shape Chainlink Data Feeds and Proof
/// of Reserve expose. Inlined instead of vendored because we need one interface
/// and don't want a full Chainlink import tree.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/// @title ProofOfReserveConsumer
/// @notice Reads a Chainlink Proof of Reserve feed and drives a circuit breaker
///         over minting for a backed RWA token. If off-chain reserves fall
///         below the on-chain circulating supply (adjusted for a configurable
///         over-collateralization ratio), minting is auto-paused until reserves
///         are restored.
///
///         PoR is the "continuous verification" primitive from the Chainlink
///         stack — replaces the opaque, quarterly, PDF-attestation model that
///         has been the historical source of tokenized-asset trust failures.
///         21.co (ARK 21Shares BTC ETF), Backed, Bedrock, and Bancolombia all
///         use PoR-driven circuit breakers as their production trust layer.
///
///         Integration pattern: an issuer's minting contract reads
///         `canMint(currentSupply, mintAmount)` before every mint. Reverts
///         with a specific reason if the mint would cross the reserve threshold.
contract ProofOfReserveConsumer is AccessControl {
    bytes32 public constant PARAMS_ADMIN_ROLE = keccak256("PARAMS_ADMIN_ROLE");

    /// Basis points denominator. 10_000 = 100%.
    uint256 public constant BPS_DENOM = 10_000;

    AggregatorV3Interface public immutable reserveFeed;
    /// Feed's decimals (cached at deploy — Chainlink feeds' decimals() is view
    /// but reading it every check burns a needless gas roundtrip).
    uint8 public immutable feedDecimals;
    /// Token's decimals (18 for most ERC-20s, 6 for USDC/USDT).
    uint8 public immutable tokenDecimals;
    /// Required over-collateralization in bps. e.g. 10_500 = 105% (issuer must
    /// hold reserves ≥ 105% of circulating supply).
    uint256 public overCollateralBps;
    /// Max acceptable age of a PoR update, in seconds. Feeds that go stale
    /// beyond this are treated as insolvent — safer than trusting a stale value.
    uint32 public maxStalenessSec;

    event ParamsUpdated(uint256 overCollateralBps, uint32 maxStalenessSec);
    event CircuitBreakerTripped(
        uint256 circulatingSupply,
        uint256 reservesScaled,
        uint256 requiredScaled,
        string reason
    );

    error FeedStale(uint256 age, uint32 maxAge);
    error FeedInvalid(int256 answer, uint80 roundId, uint80 answeredIn);
    error InsufficientReserves(uint256 circulatingSupply, uint256 reservesScaled, uint256 requiredScaled);

    constructor(
        address admin,
        address feed,
        uint8 tokenDecimals_,
        uint256 overCollateralBps_,
        uint32 maxStalenessSec_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PARAMS_ADMIN_ROLE, admin);
        reserveFeed = AggregatorV3Interface(feed);
        feedDecimals = AggregatorV3Interface(feed).decimals();
        tokenDecimals = tokenDecimals_;
        require(overCollateralBps_ >= BPS_DENOM, "overCollateralBps < 100%");
        overCollateralBps = overCollateralBps_;
        maxStalenessSec = maxStalenessSec_;
    }

    function setParams(uint256 overCollateralBps_, uint32 maxStalenessSec_) external onlyRole(PARAMS_ADMIN_ROLE) {
        require(overCollateralBps_ >= BPS_DENOM, "overCollateralBps < 100%");
        overCollateralBps = overCollateralBps_;
        maxStalenessSec = maxStalenessSec_;
        emit ParamsUpdated(overCollateralBps_, maxStalenessSec_);
    }

    /// @notice Read the current reserve balance from the PoR feed, scaled to
    ///         the token's decimals. Reverts on stale or invalid data.
    function currentReserves() public view returns (uint256 reservesInTokenDecimals) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredIn) = reserveFeed.latestRoundData();
        if (answer <= 0 || answeredIn < roundId) revert FeedInvalid(answer, roundId, answeredIn);
        uint256 age = block.timestamp - updatedAt;
        if (age > maxStalenessSec) revert FeedStale(age, maxStalenessSec);
        return _scale(uint256(answer), feedDecimals, tokenDecimals);
    }

    /// @notice Returns true iff `currentSupply + mintAmount` remains covered
    ///         by reserves at the configured over-collateralization ratio.
    ///         Callers that MOVE FUNDS (i.e. actually mint) should use
    ///         `requireCanMint` — the view here is for UI display.
    function canMint(uint256 currentSupply, uint256 mintAmount) external view returns (bool ok, uint256 reserves, uint256 required) {
        reserves = currentReserves();
        uint256 postMintSupply = currentSupply + mintAmount;
        required = (postMintSupply * overCollateralBps) / BPS_DENOM;
        ok = reserves >= required;
    }

    /// @notice Reverts if the requested mint would violate the reserve
    ///         threshold. Use in the mint path of the token contract, before
    ///         actually calling _mint.
    function requireCanMint(uint256 currentSupply, uint256 mintAmount) external {
        uint256 reserves = currentReserves();
        uint256 postMintSupply = currentSupply + mintAmount;
        uint256 required = (postMintSupply * overCollateralBps) / BPS_DENOM;
        if (reserves < required) {
            emit CircuitBreakerTripped(currentSupply, reserves, required, "reserves below over-collateral threshold");
            revert InsufficientReserves(currentSupply, reserves, required);
        }
    }

    /// @dev Scale between two decimal precisions (used to align feed decimals
    ///      with token decimals). Both directions supported.
    function _scale(uint256 amount, uint8 from, uint8 to) internal pure returns (uint256) {
        if (from == to) return amount;
        if (from < to) return amount * (10 ** (to - from));
        return amount / (10 ** (from - to));
    }
}
