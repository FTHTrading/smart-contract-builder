// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/payments/PaymentRailRegistry.sol";
import "../contracts/treasury/TreasuryPolicyEngine.sol";

contract TreasuryPolicyEngineTest is Test {
    PaymentRailRegistry public railRegistry;
    TreasuryPolicyEngine public policyEngine;

    address public admin = address(1);

    function setUp() public {
        vm.startPrank(admin);
        railRegistry = new PaymentRailRegistry(admin);
        policyEngine = new TreasuryPolicyEngine(admin);
        vm.stopPrank();
    }

    function test_DefaultPaymentRail_Fedwire() public view {
        PaymentRailRegistry.PaymentRail memory fedwire = railRegistry.getRail("FEDWIRE");
        assertEq(fedwire.name, "Federal Reserve Wire Network");
        assertEq(fedwire.jurisdiction, "US");
    }

    function test_MapAssetToPaymentRail() public {
        vm.startPrank(admin);
        railRegistry.mapAssetToRail("USDC", "FEDNOW");
        railRegistry.mapAssetToRail("USDC", "FEDWIRE");
        vm.stopPrank();

        bytes32[] memory rails = railRegistry.getAssetRails("USDC");
        assertEq(rails.length, 2);
    }

    function test_CreateAndValidateTreasuryPolicy() public {
        vm.prank(admin);
        bytes32 policyId = policyEngine.createPolicy(
            "Unykorn Corporate Treasury",
            2000, // 20% min cash reserve
            4000, // 40% max single asset
            true,
            true
        );

        bool valid = policyEngine.validateAllocation(policyId, 2500, 3000);
        assertTrue(valid);

        bool invalid = policyEngine.validateAllocation(policyId, 1500, 3000);
        assertFalse(invalid);
    }
}
