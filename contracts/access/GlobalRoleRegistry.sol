// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title GlobalRoleRegistry
 * @notice Centralized Role Permissioning Registry defining standard roles across the institutional operating system.
 */
contract GlobalRoleRegistry is AccessControl {
    bytes32 public constant SYSTEM_ADMIN_ROLE     = keccak256("SYSTEM_ADMIN_ROLE");
    bytes32 public constant COMPLIANCE_ADMIN_ROLE = keccak256("COMPLIANCE_ADMIN_ROLE");
    bytes32 public constant AUDITOR_ROLE          = keccak256("AUDITOR_ROLE");
    bytes32 public constant CUSTODIAN_ROLE        = keccak256("CUSTODIAN_ROLE");
    bytes32 public constant ISSUER_ROLE           = keccak256("ISSUER_ROLE");
    bytes32 public constant FUND_MANAGER_ROLE     = keccak256("FUND_MANAGER_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SYSTEM_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ADMIN_ROLE, admin);
        _grantRole(AUDITOR_ROLE, admin);
        _grantRole(CUSTODIAN_ROLE, admin);
        _grantRole(ISSUER_ROLE, admin);
        _grantRole(FUND_MANAGER_ROLE, admin);
        _grantRole(TREASURY_MANAGER_ROLE, admin);
    }
}
