// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/custody/CustodyRegistry.sol";
import "../contracts/access/GlobalRoleRegistry.sol";
import "../contracts/audit/AuditRegistry.sol";

contract CustodyAndAuditRegistryTest is Test {
    CustodyRegistry public custodyRegistry;
    GlobalRoleRegistry public roleRegistry;
    AuditRegistry public auditRegistry;

    address public admin = address(1);

    function setUp() public {
        vm.startPrank(admin);
        custodyRegistry = new CustodyRegistry(admin);
        roleRegistry = new GlobalRoleRegistry(admin);
        auditRegistry = new AuditRegistry(admin);
        vm.stopPrank();
    }

    function test_DefaultCustody_BNYMellon() public view {
        CustodyRegistry.CustodyMapping memory m = custodyRegistry.getCustodyMapping("BUIDL");

        assertEq(m.custodianName, "BNY Mellon");
        assertEq(m.reserveRatioBps, 10000);
        assertTrue(m.active);
    }

    function test_GlobalRolesInitialized() public view {
        assertTrue(roleRegistry.hasRole(roleRegistry.SYSTEM_ADMIN_ROLE(), admin));
        assertTrue(roleRegistry.hasRole(roleRegistry.COMPLIANCE_ADMIN_ROLE(), admin));
        assertTrue(roleRegistry.hasRole(roleRegistry.AUDITOR_ROLE(), admin));
    }

    function test_LogAuditAction() public {
        vm.prank(admin);
        uint256 entryId = auditRegistry.logAction(
            keccak256("SETTLEMENT_SWAP_1"),
            "SETTLEMENT",
            "Atomic swap USDC -> RLUSD completed",
            "StablecoinSettlementHub"
        );

        assertEq(entryId, 0);
        assertEq(auditRegistry.getAuditLogCount(), 1);
    }
}
