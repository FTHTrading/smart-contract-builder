// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/compliance/IdentityRegistry.sol";
import "../contracts/compliance/SanctionsRegistry.sol";
import "../contracts/compliance/JurisdictionManager.sol";
import "../contracts/compliance/ComplianceOracle.sol";

contract ComplianceStackTest is Test {
    IdentityRegistry public identityRegistry;
    SanctionsRegistry public sanctionsRegistry;
    JurisdictionManager public jurisdictionManager;
    ComplianceOracle public oracle;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);

    function setUp() public {
        vm.startPrank(admin);
        identityRegistry = new IdentityRegistry(admin);
        sanctionsRegistry = new SanctionsRegistry(admin);
        jurisdictionManager = new JurisdictionManager(admin);

        oracle = new ComplianceOracle(
            address(identityRegistry),
            address(sanctionsRegistry),
            address(jurisdictionManager),
            admin
        );
        vm.stopPrank();
    }

    function test_VerifiedInvestor_Approved() public {
        vm.startPrank(admin);
        identityRegistry.registerIdentity(
            alice,
            keccak256("ALICE_ID"),
            "Alice Smith",
            "US",
            true, // kyc
            false, // kyb
            true,  // accredited
            false, // institutional
            365 days
        );
        vm.stopPrank();

        assertTrue(oracle.validateInvestor(alice));
    }

    function test_SanctionedInvestor_Blocked() public {
        vm.startPrank(admin);
        identityRegistry.registerIdentity(
            alice,
            keccak256("ALICE_ID"),
            "Alice Smith",
            "US",
            true,
            false,
            true,
            false,
            365 days
        );

        sanctionsRegistry.sanctionAccount(alice);
        vm.stopPrank();

        assertFalse(oracle.validateInvestor(alice));
    }

    function test_Jurisdiction_Validation() public {
        vm.startPrank(admin);
        jurisdictionManager.addJurisdiction("XX", "Restricted Region", false, false, false);

        identityRegistry.registerIdentity(
            bob,
            keccak256("BOB_ID"),
            "Bob Corp",
            "XX",
            true,
            true,
            true,
            true,
            365 days
        );
        vm.stopPrank();

        assertFalse(oracle.validateInvestor(bob));
    }
}
