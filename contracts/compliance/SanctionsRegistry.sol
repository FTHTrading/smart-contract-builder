// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title SanctionsRegistry
 * @notice Shared sanctions and OFAC compliance engine for asset contracts.
 */
contract SanctionsRegistry is AccessControl {
    bytes32 public constant SANCTIONS_ADMIN_ROLE = keccak256("SANCTIONS_ADMIN_ROLE");

    mapping(address => bool) private _sanctioned;

    event AccountSanctioned(address indexed account);
    event AccountUnsanctioned(address indexed account);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SANCTIONS_ADMIN_ROLE, admin);
    }

    function sanctionAccount(address account) external onlyRole(SANCTIONS_ADMIN_ROLE) {
        _sanctioned[account] = true;
        emit AccountSanctioned(account);
    }

    function unsanctionAccount(address account) external onlyRole(SANCTIONS_ADMIN_ROLE) {
        _sanctioned[account] = false;
        emit AccountUnsanctioned(account);
    }

    function isSanctioned(address account) external view returns (bool) {
        return _sanctioned[account];
    }
}
