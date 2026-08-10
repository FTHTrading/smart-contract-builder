// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title IdentityRegistry
 * @notice Maintains verified identities for individuals, institutions, funds, custodians, and sovereign entities.
 */
contract IdentityRegistry is AccessControl {
    bytes32 public constant IDENTITY_VERIFIER_ROLE = keccak256("IDENTITY_VERIFIER_ROLE");

    struct Identity {
        bytes32 id;
        string entityName;
        string jurisdiction;
        bool kycVerified;
        bool kybVerified;
        bool accredited;
        bool institutional;
        bool active;
        uint256 expiry;
    }

    // account => Identity
    mapping(address => Identity) public identities;

    event IdentityRegistered(address indexed account, bytes32 indexed id, string entityName, string jurisdiction);
    event IdentityUpdated(address indexed account, bool kyc, bool kyb, bool accredited, bool institutional, bool active);
    event IdentityRevoked(address indexed account);

    error IdentityAlreadyExists(address account);
    error IdentityNotFound(address account);
    error IdentityExpired(address account, uint256 expiry);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(IDENTITY_VERIFIER_ROLE, admin);
    }

    function registerIdentity(
        address account,
        bytes32 id,
        string calldata entityName,
        string calldata jurisdiction,
        bool kycVerified,
        bool kybVerified,
        bool accredited,
        bool institutional,
        uint256 expiryDuration
    ) external onlyRole(IDENTITY_VERIFIER_ROLE) {
        if (identities[account].active) revert IdentityAlreadyExists(account);

        uint256 expiry = block.timestamp + expiryDuration;

        identities[account] = Identity({
            id: id,
            entityName: entityName,
            jurisdiction: jurisdiction,
            kycVerified: kycVerified,
            kybVerified: kybVerified,
            accredited: accredited,
            institutional: institutional,
            active: true,
            expiry: expiry
        });

        emit IdentityRegistered(account, id, entityName, jurisdiction);
    }

    function updateIdentity(
        address account,
        bool kycVerified,
        bool kybVerified,
        bool accredited,
        bool institutional,
        bool active,
        uint256 newExpiry
    ) external onlyRole(IDENTITY_VERIFIER_ROLE) {
        if (identities[account].id == bytes32(0)) revert IdentityNotFound(account);

        Identity storage id = identities[account];
        id.kycVerified = kycVerified;
        id.kybVerified = kybVerified;
        id.accredited = accredited;
        id.institutional = institutional;
        id.active = active;
        id.expiry = newExpiry;

        emit IdentityUpdated(account, kycVerified, kybVerified, accredited, institutional, active);
    }

    function revokeIdentity(address account) external onlyRole(IDENTITY_VERIFIER_ROLE) {
        if (!identities[account].active) revert IdentityNotFound(account);
        identities[account].active = false;
        emit IdentityRevoked(account);
    }

    function isVerified(address account) external view returns (bool) {
        Identity memory id = identities[account];
        return id.active && (id.kycVerified || id.kybVerified) && block.timestamp < id.expiry;
    }

    function isAccredited(address account) external view returns (bool) {
        Identity memory id = identities[account];
        return id.active && id.accredited && block.timestamp < id.expiry;
    }

    function isInstitutional(address account) external view returns (bool) {
        Identity memory id = identities[account];
        return id.active && id.institutional && block.timestamp < id.expiry;
    }

    function jurisdictionOf(address account) external view returns (string memory) {
        return identities[account].jurisdiction;
    }
}
