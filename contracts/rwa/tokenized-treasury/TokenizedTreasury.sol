// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Minimal interface for the transfer eligibility check. In production this
/// is the PermissionedToken's IdentityRegistry + ClaimTopicsRegistry pair,
/// wrapped so this contract can accept either the direct registry pair or
/// the Chainlink ACE credential-check.
interface IEligibilityCheck {
    function eligibleFor(address holder, uint256[] calldata requiredClaims) external view returns (bool);
}

interface INAVOracle {
    /// Returns NAV per share scaled to 1e18. Reverts on stale or invalid data.
    function navPerShare() external view returns (uint256);
}

interface IReserveGuard {
    /// Reverts if the mint would violate the reserve/circulating threshold.
    function requireCanMint(uint256 currentSupply, uint256 mintAmount) external;
}

/// @title TokenizedTreasury
/// @notice ERC-20 share of a Treasury / money-market fund portfolio. Reference
///         shapes: BlackRock BUIDL, Franklin BENJI, Ondo OUSG, Circle USYC.
///         Every share is:
///           - PermissionedToken-gated at the receiver (KYC + claim topics)
///           - Backed by an off-chain vault whose reserves are attested by
///             Chainlink Proof of Reserve; mint circuit-breakers when
///             reserves fall below a configurable over-collateral ratio
///           - Priced in currency (USDC typical) via a NAV oracle updated by
///             the fund administrator; subscribers deposit at current NAV,
///             redeemers receive at current NAV (T+1 typical settlement)
///
///         Subscribe and redeem are permission-gated by SUBSCRIPTION_ROLE
///         and REDEMPTION_ROLE — production deployments wire these to the
///         fund's transfer agent (Securitize-registered for BUIDL).
contract TokenizedTreasury is ERC20, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant SUBSCRIPTION_ROLE = keccak256("SUBSCRIPTION_ROLE");
    bytes32 public constant REDEMPTION_ROLE = keccak256("REDEMPTION_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    uint256 public constant SCALE = 1e18;

    IERC20 public immutable currency;
    IEligibilityCheck public immutable eligibilityRegistry;
    INAVOracle public navOracle;
    IReserveGuard public reserveGuard;

    /// Claim topic IDs required to receive shares. Typical: [1 = KYC, 2 = accredited].
    uint256[] private _requiredClaims;

    /// Sum of currency held for future redemptions (segregated from NAV-backing reserves).
    uint256 public redemptionQueueTotal;

    struct RedemptionRequest {
        address holder;
        uint256 shares;
        uint256 requestedAt;
        bool fulfilled;
    }

    RedemptionRequest[] public redemptionQueue;
    mapping(address => uint256[]) public holderRedemptions;

    /// T+N settlement delay in seconds (86400 = 1 day).
    uint256 public settlementDelaySec;

    event Subscribed(address indexed subscriber, uint256 currencyAmount, uint256 sharesMinted, uint256 navPerShareUsed);
    event RedemptionRequested(uint256 indexed requestId, address indexed holder, uint256 shares);
    event RedemptionFulfilled(uint256 indexed requestId, address indexed holder, uint256 shares, uint256 currencyReturned, uint256 navPerShareUsed);
    event NAVOracleUpdated(address oracle);
    event ReserveGuardUpdated(address guard);
    event RequiredClaimsUpdated(uint256[] claims);

    error ReceiverNotEligible(address receiver);
    error SettlementNotReady(uint256 requestedAt, uint256 readyAt);
    error RequestAlreadyFulfilled(uint256 requestId);
    error InsufficientQueueBalance(uint256 needed, uint256 available);

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address currency_,
        address eligibility_,
        address navOracle_,
        address reserveGuard_,
        uint256[] memory requiredClaims_,
        uint256 settlementDelaySec_
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SUBSCRIPTION_ROLE, admin);
        _grantRole(REDEMPTION_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);
        currency = IERC20(currency_);
        eligibilityRegistry = IEligibilityCheck(eligibility_);
        navOracle = INAVOracle(navOracle_);
        reserveGuard = IReserveGuard(reserveGuard_);
        _requiredClaims = requiredClaims_;
        settlementDelaySec = settlementDelaySec_;
    }

    // ---- Admin ----

    function setNAVOracle(address o) external onlyRole(ORACLE_ADMIN_ROLE) {
        navOracle = INAVOracle(o);
        emit NAVOracleUpdated(o);
    }
    function setReserveGuard(address g) external onlyRole(ORACLE_ADMIN_ROLE) {
        reserveGuard = IReserveGuard(g);
        emit ReserveGuardUpdated(g);
    }
    function setRequiredClaims(uint256[] calldata claims) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete _requiredClaims;
        for (uint256 i = 0; i < claims.length; i++) _requiredClaims.push(claims[i]);
        emit RequiredClaimsUpdated(claims);
    }
    function requiredClaims() external view returns (uint256[] memory) {
        return _requiredClaims;
    }
    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ---- Transfer eligibility (via IEligibilityCheck) ----

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        if (to != address(0)) {
            if (!eligibilityRegistry.eligibleFor(to, _requiredClaims)) {
                revert ReceiverNotEligible(to);
            }
        }
        super._update(from, to, value);
    }

    // ---- Subscription (mint at current NAV) ----

    /// @notice Subscribe by depositing currency at the current NAV per share.
    ///         Mint is gated by both the eligibility check AND the reserve
    ///         circuit breaker (via reserveGuard.requireCanMint).
    function subscribe(uint256 currencyAmount, address recipient) external onlyRole(SUBSCRIPTION_ROLE) {
        uint256 nav = navOracle.navPerShare();
        uint256 sharesToMint = (currencyAmount * SCALE) / nav;
        reserveGuard.requireCanMint(totalSupply(), sharesToMint);
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        _mint(recipient, sharesToMint);
        emit Subscribed(recipient, currencyAmount, sharesToMint, nav);
    }

    // ---- Redemption (T+N settlement) ----

    function requestRedemption(uint256 shares) external returns (uint256 requestId) {
        // Burn immediately so holder cannot double-redeem or transfer.
        _burn(msg.sender, shares);
        requestId = redemptionQueue.length;
        redemptionQueue.push(RedemptionRequest({
            holder: msg.sender,
            shares: shares,
            requestedAt: block.timestamp,
            fulfilled: false
        }));
        holderRedemptions[msg.sender].push(requestId);
        emit RedemptionRequested(requestId, msg.sender, shares);
    }

    /// @notice Fulfilled by the fund's transfer agent once the off-chain
    ///         portfolio has liquidated the pro-rata slice into currency.
    ///         NAV oracle is read at fulfillment time — same-day NAV per share.
    function fulfillRedemption(uint256 requestId) external onlyRole(REDEMPTION_ROLE) {
        RedemptionRequest storage r = redemptionQueue[requestId];
        if (r.fulfilled) revert RequestAlreadyFulfilled(requestId);
        uint256 readyAt = r.requestedAt + settlementDelaySec;
        if (block.timestamp < readyAt) revert SettlementNotReady(r.requestedAt, readyAt);

        uint256 nav = navOracle.navPerShare();
        uint256 currencyOut = (r.shares * nav) / SCALE;
        r.fulfilled = true;
        // Sponsor must have pre-funded the queue via currency transfer.
        // If the sponsor uses fund_escrow style flow, that's a separate
        // capability; this contract just pays out.
        redemptionQueueTotal += currencyOut;
        currency.safeTransfer(r.holder, currencyOut);
        emit RedemptionFulfilled(requestId, r.holder, r.shares, currencyOut, nav);
    }

    function redemptionCount() external view returns (uint256) {
        return redemptionQueue.length;
    }
    function redemptionsOf(address holder) external view returns (uint256[] memory) {
        return holderRedemptions[holder];
    }
}
