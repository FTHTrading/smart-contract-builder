// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/workflow/WorkflowEngine.sol";
import "../contracts/policy/PolicyEngine.sol";

contract WorkflowAndPolicyEngineTest is Test {
    WorkflowEngine public workflowEngine;
    PolicyEngine public policyEngine;

    address public admin = address(1);

    function setUp() public {
        vm.startPrank(admin);
        workflowEngine = new WorkflowEngine(admin);
        policyEngine = new PolicyEngine(admin);
        vm.stopPrank();
    }

    function test_StartAndAdvanceWorkflow() public {
        vm.startPrank(admin);
        bytes32 wfId = workflowEngine.startWorkflow("New Institutional Asset Issuance", "USDF");

        workflowEngine.advanceWorkflowStage(wfId, WorkflowEngine.WorkflowStage.IdentityVerified);
        workflowEngine.advanceWorkflowStage(wfId, WorkflowEngine.WorkflowStage.ComplianceReviewed);
        workflowEngine.advanceWorkflowStage(wfId, WorkflowEngine.WorkflowStage.Activated);
        vm.stopPrank();

        (
            bytes32 id,
            string memory name,
            string memory symbol,
            WorkflowEngine.WorkflowStage stage,
            address initiator,
            uint256 cAt,
            uint256 uAt,
            bool completed
        ) = workflowEngine.workflows(wfId);

        assertEq(symbol, "USDF");
        assertTrue(completed);
        assertEq(uint256(stage), uint256(WorkflowEngine.WorkflowStage.Activated));
    }

    function test_EvaluatePolicyRule() public view {
        bytes32 ruleId = keccak256("INSTITUTIONAL_DEFAULT_POLICY");

        (bool allowed, string memory reason) = policyEngine.evaluatePolicy(ruleId, 3000, block.timestamp);
        assertTrue(allowed);
        assertEq(reason, "Policy compliant");

        (bool blocked, string memory reasonBlocked) = policyEngine.evaluatePolicy(ruleId, 4500, block.timestamp);
        assertFalse(blocked);
        assertEq(reasonBlocked, "Concentration cap exceeded");
    }
}
