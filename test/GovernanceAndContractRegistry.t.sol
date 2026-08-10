// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/governance/GovernanceRegistry.sol";
import "../contracts/core/ContractRegistry.sol";

contract GovernanceAndContractRegistryTest is Test {
    GovernanceRegistry public govRegistry;
    ContractRegistry public contractRegistry;

    address public admin = address(1);

    function setUp() public {
        vm.startPrank(admin);
        govRegistry = new GovernanceRegistry(admin);
        contractRegistry = new ContractRegistry(admin);
        vm.stopPrank();
    }

    function test_ContractRegistry_Defaults() public view {
        ContractRegistry.ContractVersion memory ver = contractRegistry.getContract("MultiChainRegistry");

        assertEq(ver.contractName, "MultiChainRegistry");
        assertEq(ver.majorVersion, 1);
        assertEq(ver.minorVersion, 1);
        assertTrue(ver.active);
    }

    function test_CreateAndApproveProposal() public {
        vm.startPrank(admin);
        bytes32 proposalId = govRegistry.createProposal(
            "Add Canton Participant DTCC",
            "Register DTCC as a verified Canton Custodian node",
            address(0x123),
            abi.encodeWithSignature("register()")
        );

        govRegistry.approveProposal(proposalId);
        vm.stopPrank();

        (
            bytes32 id,
            string memory title,
            string memory desc,
            address target,
            bytes memory data,
            GovernanceRegistry.ProposalStatus status,
            address proposer,
            address approver,
            uint256 pAt,
            uint256 eAt
        ) = govRegistry.proposals(proposalId);

        assertEq(title, "Add Canton Participant DTCC");
        assertEq(uint256(status), uint256(GovernanceRegistry.ProposalStatus.Approved));
    }
}
