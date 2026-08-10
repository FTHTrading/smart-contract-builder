// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AuditRegistry
 * @notice Cryptographic Action Auditing & Log Registry tracking operator, timestamp, actionHash, reason, and source.
 */
contract AuditRegistry is AccessControl {
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    struct AuditEntry {
        uint256 entryId;
        address operator;
        uint256 timestamp;
        bytes32 actionHash;
        string actionType; // e.g. "SETTLEMENT", "NAV_UPDATE", "SANCTION"
        string reason;
        string source;
    }

    AuditEntry[] public auditLogs;

    event AuditLogged(uint256 indexed entryId, address indexed operator, string actionType, bytes32 actionHash);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AUDITOR_ROLE, admin);
    }

    function logAction(
        bytes32 actionHash,
        string calldata actionType,
        string calldata reason,
        string calldata source
    ) external returns (uint256 entryId) {
        entryId = auditLogs.length;

        auditLogs.push(AuditEntry({
            entryId: entryId,
            operator: msg.sender,
            timestamp: block.timestamp,
            actionHash: actionHash,
            actionType: actionType,
            reason: reason,
            source: source
        }));

        emit AuditLogged(entryId, msg.sender, actionType, actionHash);
    }

    function getAuditLogCount() external view returns (uint256) {
        return auditLogs.length;
    }
}
