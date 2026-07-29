// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title IdentityRegistry
/// @notice Maps investor address → verifiable claim topic set. A claim topic is
///         an integer identifying a specific attestation (1 = KYC, 2 = accredited,
///         3 = jurisdiction-US, 4 = jurisdiction-EU, etc.). The PermissionedToken
///         reads this registry at every transfer to enforce eligibility.
///
///         Real ONCHAINID uses ERC-734/735 signed claims per investor; this
///         simplified version uses direct on-chain flags gated by TRUSTED_ISSUER_ROLE.
///         Wire up ONCHAINID when investors need to prove claims across
///         multiple issuers.
contract IdentityRegistry is AccessControl {
    bytes32 public constant TRUSTED_ISSUER_ROLE = keccak256("TRUSTED_ISSUER_ROLE");

    /// investor → topicId → holdsClaim
    mapping(address => mapping(uint256 => bool)) public hasClaim;
    /// investor → registered
    mapping(address => bool) public isRegistered;

    event InvestorRegistered(address indexed investor, address indexed issuer);
    event InvestorRemoved(address indexed investor, address indexed issuer);
    event ClaimAdded(address indexed investor, uint256 indexed topicId, address indexed issuer);
    event ClaimRevoked(address indexed investor, uint256 indexed topicId, address indexed issuer);

    error NotRegistered(address investor);
    error ZeroAddress();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TRUSTED_ISSUER_ROLE, admin);
    }

    function registerInvestor(address investor) external onlyRole(TRUSTED_ISSUER_ROLE) {
        if (investor == address(0)) revert ZeroAddress();
        isRegistered[investor] = true;
        emit InvestorRegistered(investor, msg.sender);
    }

    function removeInvestor(address investor) external onlyRole(TRUSTED_ISSUER_ROLE) {
        isRegistered[investor] = false;
        emit InvestorRemoved(investor, msg.sender);
    }

    function addClaim(address investor, uint256 topicId) external onlyRole(TRUSTED_ISSUER_ROLE) {
        if (!isRegistered[investor]) revert NotRegistered(investor);
        hasClaim[investor][topicId] = true;
        emit ClaimAdded(investor, topicId, msg.sender);
    }

    function revokeClaim(address investor, uint256 topicId) external onlyRole(TRUSTED_ISSUER_ROLE) {
        hasClaim[investor][topicId] = false;
        emit ClaimRevoked(investor, topicId, msg.sender);
    }

    /// @notice Returns true iff the investor is registered AND holds every
    ///         claim in the required set.
    function eligibleFor(address investor, uint256[] calldata requiredClaims) external view returns (bool) {
        if (!isRegistered[investor]) return false;
        for (uint256 i = 0; i < requiredClaims.length; i++) {
            if (!hasClaim[investor][requiredClaims[i]]) return false;
        }
        return true;
    }
}
