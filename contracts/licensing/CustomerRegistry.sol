// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CustomerRegistry
 * @notice Enterprise Customer Registry tracking institutional entities, subscriptions, and licensing tiers.
 */
contract CustomerRegistry is AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    enum LicenseTier { Free, Standard, Institutional, SovereignEnterprise }

    struct CustomerProfile {
        bytes32 customerId;
        string legalName;
        string lei;
        LicenseTier tier;
        uint256 registeredAt;
        uint256 expiresAt;
        bool active;
    }

    mapping(bytes32 => CustomerProfile) public customers;
    mapping(address => bytes32) public addressToCustomer;

    event CustomerRegistered(bytes32 indexed customerId, string legalName, string lei, LicenseTier tier);
    event CustomerTierUpdated(bytes32 indexed customerId, LicenseTier newTier, uint256 newExpiresAt);
    event CustomerStatusChanged(bytes32 indexed customerId, bool active);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function registerCustomer(
        bytes32 customerId,
        address primaryAddress,
        string calldata legalName,
        string calldata lei,
        LicenseTier tier,
        uint256 durationSec
    ) external onlyRole(REGISTRAR_ROLE) {
        uint256 expiresAt = block.timestamp + durationSec;
        customers[customerId] = CustomerProfile({
            customerId: customerId,
            legalName: legalName,
            lei: lei,
            tier: tier,
            registeredAt: block.timestamp,
            expiresAt: expiresAt,
            active: true
        });
        addressToCustomer[primaryAddress] = customerId;

        emit CustomerRegistered(customerId, legalName, lei, tier);
    }

    function updateCustomerTier(bytes32 customerId, LicenseTier newTier, uint256 additionalSec) external onlyRole(REGISTRAR_ROLE) {
        CustomerProfile storage c = customers[customerId];
        require(c.active, "Customer inactive");
        c.tier = newTier;
        c.expiresAt = block.timestamp + additionalSec;

        emit CustomerTierUpdated(customerId, newTier, c.expiresAt);
    }

    function isEntitled(address account, LicenseTier requiredTier) external view returns (bool) {
        bytes32 cid = addressToCustomer[account];
        CustomerProfile memory c = customers[cid];
        if (!c.active || block.timestamp > c.expiresAt) return false;
        return uint8(c.tier) >= uint8(requiredTier);
    }
}
