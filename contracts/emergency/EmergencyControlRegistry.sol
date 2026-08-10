// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EmergencyControlRegistry
 * @notice Enterprise disaster recovery, emergency pause controls, key rotation, and recovery management registry.
 */
contract EmergencyControlRegistry is AccessControl, Pausable {
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

    struct RecoveryKey {
        address keyAddress;
        string keyLabel;
        bool active;
    }

    mapping(address => RecoveryKey) public recoveryKeys;

    event EmergencyPauseTriggered(address indexed admin, string reason);
    event EmergencyUnpauseTriggered(address indexed admin);
    event RecoveryKeyRegistered(address indexed keyAddress, string keyLabel);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EMERGENCY_ADMIN_ROLE, admin);
    }

    function registerRecoveryKey(address keyAddress, string calldata keyLabel) external onlyRole(EMERGENCY_ADMIN_ROLE) {
        recoveryKeys[keyAddress] = RecoveryKey({
            keyAddress: keyAddress,
            keyLabel: keyLabel,
            active: true
        });

        emit RecoveryKeyRegistered(keyAddress, keyLabel);
    }

    function triggerEmergencyPause(string calldata reason) external onlyRole(EMERGENCY_ADMIN_ROLE) {
        _pause();
        emit EmergencyPauseTriggered(msg.sender, reason);
    }

    function triggerEmergencyUnpause() external onlyRole(EMERGENCY_ADMIN_ROLE) {
        _unpause();
        emit EmergencyUnpauseTriggered(msg.sender);
    }
}
