// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title MilestoneRegistry
/// @notice Inspector-attested milestone ledger. Field naming follows AIA G703
///         "Continuation Sheet" columns so that off-chain draw applications and
///         on-chain records reconcile 1:1.
contract MilestoneRegistry is AccessControl {
    bytes32 public constant ROLE_INSPECTOR = keccak256("ROLE_INSPECTOR");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    /// @dev Mirrors AIA G703 columns A-I. Values are in currency-atomic units
    ///      (e.g. USDC 6-decimals). percentComplete is in basis points.
    struct Milestone {
        uint256 id;                      // AIA col A (line item number)
        bytes32 descriptionHash;         // AIA col B (description of work)
        uint256 scheduledValue;          // AIA col C
        uint256 workCompletedPrevious;   // AIA col D
        uint256 workCompletedThisPeriod; // AIA col E
        uint256 materialsPresentlyStored;// AIA col F
        uint256 totalCompletedAndStored; // AIA col G  = D + E + F
        uint256 percentComplete;         // AIA col H  = G / C, in bps
        uint256 balanceToFinish;         // AIA col I  = C - G
        uint256 lastAttestationAt;
        bool exists;
    }

    mapping(uint256 => Milestone) private _milestones;

    event MilestoneDefined(uint256 indexed id, bytes32 descriptionHash, uint256 scheduledValue);
    event MilestoneAttested(
        uint256 indexed id,
        address indexed inspector,
        uint256 workCompletedThisPeriod,
        uint256 materialsPresentlyStored,
        uint256 totalCompletedAndStored,
        uint256 percentComplete
    );

    error UnknownMilestone(uint256 id);
    error MilestoneAlreadyExists(uint256 id);
    error AttestationOverruns(uint256 id, uint256 total, uint256 scheduledValue);

    constructor(address admin, address inspector) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ROLE_ADMIN, admin);
        _grantRole(ROLE_INSPECTOR, inspector);
    }

    /// @notice Register a milestone from the project's schedule of values.
    function defineMilestone(
        uint256 id,
        bytes32 descriptionHash,
        uint256 scheduledValue
    ) external onlyRole(ROLE_ADMIN) {
        if (_milestones[id].exists) revert MilestoneAlreadyExists(id);
        _milestones[id] = Milestone({
            id: id,
            descriptionHash: descriptionHash,
            scheduledValue: scheduledValue,
            workCompletedPrevious: 0,
            workCompletedThisPeriod: 0,
            materialsPresentlyStored: 0,
            totalCompletedAndStored: 0,
            percentComplete: 0,
            balanceToFinish: scheduledValue,
            lastAttestationAt: 0,
            exists: true
        });
        emit MilestoneDefined(id, descriptionHash, scheduledValue);
    }

    /// @notice Inspector records a new attestation for a milestone id. Values are the
    ///         *cumulative* period-close numbers, not deltas. Overrunning the scheduled
    ///         value requires an off-chain change order + a re-define; on-chain we reject.
    function attest(
        uint256 id,
        uint256 workCompletedThisPeriod,
        uint256 materialsPresentlyStored
    ) external onlyRole(ROLE_INSPECTOR) {
        Milestone storage m = _milestones[id];
        if (!m.exists) revert UnknownMilestone(id);

        uint256 previous = m.totalCompletedAndStored;
        uint256 total = previous + workCompletedThisPeriod + materialsPresentlyStored;
        if (total > m.scheduledValue) {
            revert AttestationOverruns(id, total, m.scheduledValue);
        }

        m.workCompletedPrevious = previous;
        m.workCompletedThisPeriod = workCompletedThisPeriod;
        m.materialsPresentlyStored = materialsPresentlyStored;
        m.totalCompletedAndStored = total;
        m.percentComplete = m.scheduledValue == 0
            ? 0
            : (total * 10_000) / m.scheduledValue;
        m.balanceToFinish = m.scheduledValue - total;
        m.lastAttestationAt = block.timestamp;

        emit MilestoneAttested(
            id,
            msg.sender,
            workCompletedThisPeriod,
            materialsPresentlyStored,
            total,
            m.percentComplete
        );
    }

    /// @notice Returns the cumulative dollar amount attested through the last inspection,
    ///         and whether the milestone has ever been attested.
    function attestedThrough(uint256 id) external view returns (uint256 amount, bool attested) {
        Milestone storage m = _milestones[id];
        if (!m.exists) return (0, false);
        return (m.totalCompletedAndStored, m.lastAttestationAt != 0);
    }

    function getMilestone(uint256 id) external view returns (Milestone memory) {
        Milestone storage m = _milestones[id];
        if (!m.exists) revert UnknownMilestone(id);
        return m;
    }
}
