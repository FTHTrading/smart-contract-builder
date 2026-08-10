// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title WorkflowEngine
 * @notice Institutional Business Process Engine orchestrating multi-stage workflows (Asset Issuance, Onboarding, Rebalancing, Custody Transfer).
 */
contract WorkflowEngine is AccessControl {
    bytes32 public constant WORKFLOW_ADMIN_ROLE = keccak256("WORKFLOW_ADMIN_ROLE");

    enum WorkflowStage {
        Created,
        IdentityVerified,
        ComplianceReviewed,
        LegalDocumented,
        CustodianAssigned,
        ValuationConfigured,
        Activated
    }

    struct Workflow {
        bytes32 workflowId;
        string name;
        string assetOrEntitySymbol;
        WorkflowStage stage;
        address initiator;
        uint256 createdAt;
        uint256 updatedAt;
        bool completed;
    }

    // workflowId => Workflow
    mapping(bytes32 => Workflow) public workflows;
    bytes32[] public workflowKeys;

    event WorkflowStarted(bytes32 indexed workflowId, string name, string assetOrEntitySymbol);
    event WorkflowStageAdvanced(bytes32 indexed workflowId, WorkflowStage indexed newStage);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(WORKFLOW_ADMIN_ROLE, admin);
    }

    function startWorkflow(string calldata name, string calldata assetOrEntitySymbol) external onlyRole(WORKFLOW_ADMIN_ROLE) returns (bytes32 workflowId) {
        workflowId = keccak256(abi.encodePacked(name, assetOrEntitySymbol, block.timestamp));

        workflows[workflowId] = Workflow({
            workflowId: workflowId,
            name: name,
            assetOrEntitySymbol: assetOrEntitySymbol,
            stage: WorkflowStage.Created,
            initiator: msg.sender,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            completed: false
        });

        workflowKeys.push(workflowId);
        emit WorkflowStarted(workflowId, name, assetOrEntitySymbol);
    }

    function advanceWorkflowStage(bytes32 workflowId, WorkflowStage newStage) external onlyRole(WORKFLOW_ADMIN_ROLE) {
        Workflow storage w = workflows[workflowId];
        require(!w.completed, "Workflow completed");

        w.stage = newStage;
        w.updatedAt = block.timestamp;
        if (newStage == WorkflowStage.Activated) {
            w.completed = true;
        }

        emit WorkflowStageAdvanced(workflowId, newStage);
    }
}
