// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NAVOracle
 * @notice On-chain Net Asset Value (NAV) pricing oracle for tokenized funds, private credit pools, and treasuries with auditor attestations.
 */
contract NAVOracle is AccessControl {
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    bytes32 public constant NAV_UPDATER_ROLE = keccak256("NAV_UPDATER_ROLE");

    struct NAVReport {
        bytes32 fundId;
        uint256 navPerShareUSD; // scaled 1e18
        uint256 totalAssetsUSD; // scaled 1e18
        uint256 totalLiabilitiesUSD;
        uint256 updatedAt;
        address auditor;
        bytes32 attestationHash;
        bool active;
    }

    // fundId => NAVReport
    mapping(bytes32 => NAVReport) public navReports;

    event NAVUpdated(bytes32 indexed fundId, uint256 navPerShareUSD, uint256 totalAssetsUSD, address indexed auditor);

    error InvalidNAVValue();
    error StaleNAVReport(bytes32 fundId, uint256 updatedAt);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);
        _grantRole(NAV_UPDATER_ROLE, admin);
    }

    function updateNAV(
        bytes32 fundId,
        uint256 navPerShareUSD,
        uint256 totalAssetsUSD,
        uint256 totalLiabilitiesUSD,
        address auditor,
        bytes32 attestationHash
    ) external onlyRole(NAV_UPDATER_ROLE) {
        if (navPerShareUSD == 0) revert InvalidNAVValue();

        navReports[fundId] = NAVReport({
            fundId: fundId,
            navPerShareUSD: navPerShareUSD,
            totalAssetsUSD: totalAssetsUSD,
            totalLiabilitiesUSD: totalLiabilitiesUSD,
            updatedAt: block.timestamp,
            auditor: auditor,
            attestationHash: attestationHash,
            active: true
        });

        emit NAVUpdated(fundId, navPerShareUSD, totalAssetsUSD, auditor);
    }

    function getNAV(bytes32 fundId, uint256 maxStaleAge) external view returns (NAVReport memory) {
        NAVReport memory report = navReports[fundId];
        require(report.active, "NAV report inactive");
        if (block.timestamp - report.updatedAt > maxStaleAge) {
            revert StaleNAVReport(fundId, report.updatedAt);
        }
        return report;
    }
}
