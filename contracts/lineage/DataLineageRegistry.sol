// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DataLineageRegistry
 * @notice Cryptographic data provenance & oracle lineage tracking (Oracle source, submitter, approver, attestation chain).
 */
contract DataLineageRegistry is AccessControl {
    bytes32 public constant LINEAGE_ADMIN_ROLE = keccak256("LINEAGE_ADMIN_ROLE");

    struct DataLineageRecord {
        bytes32 dataHash;
        string dataLabel;
        string oracleSource; // e.g. "Chainlink", "Pyth", "Deloitte Auditor"
        address submitter;
        address approver;
        uint256 timestamp;
        bytes32 parentHash;
        bool active;
    }

    mapping(bytes32 => DataLineageRecord) public lineageRecords;

    event LineageRecorded(bytes32 indexed dataHash, string dataLabel, string oracleSource, address submitter);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LINEAGE_ADMIN_ROLE, admin);
    }

    function recordDataLineage(
        bytes32 dataHash,
        string calldata dataLabel,
        string calldata oracleSource,
        address approver,
        bytes32 parentHash
    ) external onlyRole(LINEAGE_ADMIN_ROLE) {
        lineageRecords[dataHash] = DataLineageRecord({
            dataHash: dataHash,
            dataLabel: dataLabel,
            oracleSource: oracleSource,
            submitter: msg.sender,
            approver: approver,
            timestamp: block.timestamp,
            parentHash: parentHash,
            active: true
        });

        emit LineageRecorded(dataHash, dataLabel, oracleSource, msg.sender);
    }

    function getLineage(bytes32 dataHash) external view returns (DataLineageRecord memory) {
        return lineageRecords[dataHash];
    }
}
