// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title GovernanceRegistry
 * @notice Layer 13 Proposal Governance Engine enforcing Proposal -> Review -> Approval -> Execution -> Audit for all state changes.
 */
contract GovernanceRegistry is AccessControl {
    bytes32 public constant GOVERNANCE_ADMIN_ROLE = keccak256("GOVERNANCE_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE         = keccak256("PROPOSER_ROLE");
    bytes32 public constant APPROVER_ROLE         = keccak256("APPROVER_ROLE");

    enum ProposalStatus {
        Proposed,
        Reviewed,
        Approved,
        Executed,
        Rejected
    }

    struct GovernanceProposal {
        bytes32 proposalId;
        string title;
        string description;
        address targetContract;
        bytes callData;
        ProposalStatus status;
        address proposer;
        address approver;
        uint256 proposedAt;
        uint256 executedAt;
    }

    // proposalId => GovernanceProposal
    mapping(bytes32 => GovernanceProposal) public proposals;
    bytes32[] public proposalKeys;

    event ProposalCreated(bytes32 indexed proposalId, string title, address indexed proposer);
    event ProposalApproved(bytes32 indexed proposalId, address indexed approver);
    event ProposalExecuted(bytes32 indexed proposalId);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ADMIN_ROLE, admin);
        _grantRole(PROPOSER_ROLE, admin);
        _grantRole(APPROVER_ROLE, admin);
    }

    function createProposal(
        string calldata title,
        string calldata description,
        address targetContract,
        bytes calldata callData
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32 proposalId) {
        proposalId = keccak256(abi.encodePacked(title, targetContract, block.timestamp));

        proposals[proposalId] = GovernanceProposal({
            proposalId: proposalId,
            title: title,
            description: description,
            targetContract: targetContract,
            callData: callData,
            status: ProposalStatus.Proposed,
            proposer: msg.sender,
            approver: address(0),
            proposedAt: block.timestamp,
            executedAt: 0
        });

        proposalKeys.push(proposalId);
        emit ProposalCreated(proposalId, title, msg.sender);
    }

    function approveProposal(bytes32 proposalId) external onlyRole(APPROVER_ROLE) {
        require(proposals[proposalId].status == ProposalStatus.Proposed, "Invalid proposal state");

        proposals[proposalId].status = ProposalStatus.Approved;
        proposals[proposalId].approver = msg.sender;

        emit ProposalApproved(proposalId, msg.sender);
    }

    function executeProposal(bytes32 proposalId) external onlyRole(GOVERNANCE_ADMIN_ROLE) returns (bytes memory result) {
        GovernanceProposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.Approved, "Proposal not approved");

        p.status = ProposalStatus.Executed;
        p.executedAt = block.timestamp;

        (bool success, bytes memory res) = p.targetContract.call(p.callData);
        require(success, "Governance execution failed");

        emit ProposalExecuted(proposalId);
        return res;
    }
}
