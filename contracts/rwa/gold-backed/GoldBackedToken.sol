// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IReserveGuard {
    function requireCanMint(uint256 currentSupply, uint256 mintAmount) external;
    function currentReserves() external view returns (uint256);
}

/// @title GoldBackedToken
/// @notice Commodity RWA — one token represents one troy ounce (or fractional
///         thereof, per `decimals`) of vaulted physical gold. Reference
///         shapes: PAX Gold (PAXG), Tether Gold (XAUT), Perth Mint Gold Token.
///
///         Key design points that make gold-backed tokens auditable:
///           1. Every mint MUST be gated by a ProofOfReserveConsumer that
///              reads a Chainlink PoR feed backed by the physical vault's
///              serialized-bar attestations.
///           2. Redemption for physical delivery is off-chain: burn tokens
///              on-chain, physical delivery through the reserve manager's
///              logistics (BullionVault, Perth Mint, LBMA-vaulted bars).
///           3. Reserve manager role is separate from admin — the party
///              handling physical inventory is not the party who can pause
///              the contract or upgrade its config.
contract GoldBackedToken is ERC20, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant RESERVE_MANAGER_ROLE = keccak256("RESERVE_MANAGER_ROLE");
    bytes32 public constant REDEMPTION_ORACLE_ROLE = keccak256("REDEMPTION_ORACLE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IReserveGuard public reserveGuard;

    struct RedemptionRequest {
        address holder;
        uint256 amount;
        bytes32 physicalDeliveryRef; // IBAN, vault account ref, or shipping label hash
        uint256 requestedAt;
        bool fulfilled;
        bool cancelled;
    }

    RedemptionRequest[] public redemptionQueue;

    event ReserveGuardUpdated(address guard);
    event Minted(address indexed to, uint256 amount, uint256 reservesAtMint);
    event RedemptionRequested(uint256 indexed requestId, address indexed holder, uint256 amount, bytes32 physicalDeliveryRef);
    event RedemptionFulfilled(uint256 indexed requestId, address indexed holder, uint256 amount);
    event RedemptionCancelled(uint256 indexed requestId, string reason);
    event PhysicalReserveAttested(uint256 reservesReported, uint256 timestamp);

    error RequestAlreadyClosed(uint256 requestId);
    error ZeroAmount();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address reserveManager,
        address reserveGuard_
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RESERVE_MANAGER_ROLE, reserveManager);
        _grantRole(REDEMPTION_ORACLE_ROLE, reserveManager);
        _grantRole(PAUSER_ROLE, admin);
        reserveGuard = IReserveGuard(reserveGuard_);
    }

    /// @notice Fractional troy ounces. 4 decimals is common for gold tokens
    ///         (10,000 units = 1 troy oz, matches LBMA bar granularity).
    function decimals() public pure override returns (uint8) {
        return 4;
    }

    function setReserveGuard(address g) external onlyRole(DEFAULT_ADMIN_ROLE) {
        reserveGuard = IReserveGuard(g);
        emit ReserveGuardUpdated(g);
    }

    // ---- Mint (gated by PoR circuit breaker) ----

    /// @notice Mint tokens against physical inventory. Reverts if PoR says
    ///         reserves would fall below the over-collateralization threshold
    ///         after this mint.
    function mint(address to, uint256 amount) external onlyRole(RESERVE_MANAGER_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        reserveGuard.requireCanMint(totalSupply(), amount);
        _mint(to, amount);
        emit Minted(to, amount, reserveGuard.currentReserves());
    }

    // ---- Redemption (burn on-chain, physical off-chain) ----

    /// @notice Holder burns tokens and requests physical delivery. The
    ///         `physicalDeliveryRef` is an off-chain reference (typically a
    ///         hash of the delivery instructions, keyed against a KYC'd
    ///         profile with the reserve manager).
    function requestRedemption(uint256 amount, bytes32 physicalDeliveryRef)
        external returns (uint256 requestId)
    {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
        requestId = redemptionQueue.length;
        redemptionQueue.push(RedemptionRequest({
            holder: msg.sender,
            amount: amount,
            physicalDeliveryRef: physicalDeliveryRef,
            requestedAt: block.timestamp,
            fulfilled: false,
            cancelled: false
        }));
        emit RedemptionRequested(requestId, msg.sender, amount, physicalDeliveryRef);
    }

    /// @notice Reserve manager confirms physical delivery has been executed
    ///         off-chain. Emits event for the audit trail; on-chain effect
    ///         is only marking the request as fulfilled.
    function markRedemptionFulfilled(uint256 requestId) external onlyRole(RESERVE_MANAGER_ROLE) {
        RedemptionRequest storage r = redemptionQueue[requestId];
        if (r.fulfilled || r.cancelled) revert RequestAlreadyClosed(requestId);
        r.fulfilled = true;
        emit RedemptionFulfilled(requestId, r.holder, r.amount);
    }

    /// @notice Reserve manager cancels a redemption (e.g. failed KYC, wrong
    ///         delivery ref, delivery insurance rejected). Re-mints the
    ///         burned amount back to the requester so they can retry.
    function cancelRedemption(uint256 requestId, string calldata reason)
        external onlyRole(RESERVE_MANAGER_ROLE)
    {
        RedemptionRequest storage r = redemptionQueue[requestId];
        if (r.fulfilled || r.cancelled) revert RequestAlreadyClosed(requestId);
        r.cancelled = true;
        _mint(r.holder, r.amount);
        emit RedemptionCancelled(requestId, reason);
    }

    // ---- Reserve attestation event (audit trail) ----

    /// @notice Reserve manager can post attestation events for off-chain
    ///         audit trail (in addition to the Chainlink PoR feed). These
    ///         are informational; the guarded mint uses PoR, not this event.
    function attestPhysicalReserves(uint256 reservesReported)
        external onlyRole(REDEMPTION_ORACLE_ROLE)
    {
        emit PhysicalReserveAttested(reservesReported, block.timestamp);
    }

    // ---- Admin ----

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function redemptionCount() external view returns (uint256) {
        return redemptionQueue.length;
    }
}
