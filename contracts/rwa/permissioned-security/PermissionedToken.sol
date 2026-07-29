// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IdentityRegistry } from "./IdentityRegistry.sol";
import { ClaimTopicsRegistry } from "./ClaimTopicsRegistry.sol";

/// @title PermissionedToken
/// @notice ERC-20 with transfer-time eligibility enforcement. Every transfer
///         (including mint) checks that the RECEIVER is registered in the
///         IdentityRegistry and holds every claim topic listed in the
///         ClaimTopicsRegistry. Non-eligible addresses cannot receive tokens.
///
///         Use cases:
///           - SPV equity (transfer requires KYC + accredited)
///           - Private debt tranche tokens (transfer requires KYC + qualified purchaser)
///           - Compliance-gated stablecoins
///
///         For a full T-REX deployment add a ModularCompliance contract with
///         per-holder rules (max holders per country, holding period, transfer
///         limits) — the transfer hook below is the single insertion point.
contract PermissionedToken is ERC20, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IdentityRegistry public immutable identityRegistry;
    ClaimTopicsRegistry public immutable claimTopicsRegistry;

    /// Frozen investor balances — AGENT_ROLE can freeze tokens per address (e.g.
    /// on suspected wash trading or a court order). Frozen tokens cannot be
    /// transferred out but do not affect balanceOf calls.
    mapping(address => uint256) public frozenTokens;

    event TokensFrozen(address indexed investor, uint256 amount);
    event TokensUnfrozen(address indexed investor, uint256 amount);
    event ForceTransfer(address indexed from, address indexed to, uint256 amount, string reason);

    error ReceiverNotEligible(address receiver);
    error InsufficientUnfrozenBalance(address holder, uint256 requested, uint256 available);

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address identityRegistry_,
        address claimTopicsRegistry_
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(AGENT_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        identityRegistry = IdentityRegistry(identityRegistry_);
        claimTopicsRegistry = ClaimTopicsRegistry(claimTopicsRegistry_);
    }

    /// @notice OZ v5 unified transfer hook. Runs on mint (from=0), transfer,
    ///         and burn (to=0). We only gate receivers on mint/transfer.
    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        // Burn is always allowed (to == 0). Mint (from == 0) and transfer
        // require the receiver to be eligible.
        if (to != address(0)) {
            uint256[] memory required = claimTopicsRegistry.getRequiredTopics();
            if (!identityRegistry.eligibleFor(to, required)) {
                revert ReceiverNotEligible(to);
            }
        }
        // Frozen-token enforcement on outbound transfers.
        if (from != address(0)) {
            uint256 unfrozen = balanceOf(from) - frozenTokens[from];
            if (value > unfrozen) {
                revert InsufficientUnfrozenBalance(from, value, unfrozen);
            }
        }
        super._update(from, to, value);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(AGENT_ROLE) {
        _burn(from, amount);
    }

    function freezeTokens(address investor, uint256 amount) external onlyRole(AGENT_ROLE) {
        frozenTokens[investor] += amount;
        emit TokensFrozen(investor, amount);
    }

    function unfreezeTokens(address investor, uint256 amount) external onlyRole(AGENT_ROLE) {
        if (amount > frozenTokens[investor]) amount = frozenTokens[investor];
        frozenTokens[investor] -= amount;
        emit TokensUnfrozen(investor, amount);
    }

    /// @notice Force transfer for court-ordered or key-recovery scenarios.
    ///         Bypasses eligibility check on receiver; frozen check still applies.
    ///         Reason string is emitted for audit trail — the ledger's compile
    ///         + deploy receipts already prove WHO the agent is; this proves WHY.
    function forceTransfer(address from, address to, uint256 amount, string calldata reason)
        external onlyRole(AGENT_ROLE)
    {
        uint256 unfrozen = balanceOf(from) - frozenTokens[from];
        if (amount > unfrozen) {
            revert InsufficientUnfrozenBalance(from, amount, unfrozen);
        }
        _transfer(from, to, amount);
        emit ForceTransfer(from, to, amount, reason);
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
