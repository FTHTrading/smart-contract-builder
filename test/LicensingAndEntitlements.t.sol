// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/licensing/CustomerRegistry.sol";
import "../contracts/licensing/LicenseRegistry.sol";

contract LicensingAndEntitlementsTest is Test {
    CustomerRegistry public customerRegistry;
    LicenseRegistry public licenseRegistry;

    address public admin = address(0x1);
    address public bankUser = address(0x2);
    address public retailUser = address(0x3);

    bytes32 public customerId = keccak256("CUSTOMER_JPMORGAN_CHASE");

    function setUp() public {
        vm.startPrank(admin);
        customerRegistry = new CustomerRegistry(admin);
        licenseRegistry = new LicenseRegistry(address(customerRegistry), admin);

        customerRegistry.registerCustomer(
            customerId,
            bankUser,
            "JPMorgan Chase & Co.",
            "7H6GLXDRUGV21P6S3T47",
            CustomerRegistry.LicenseTier.Institutional,
            365 days
        );
        vm.stopPrank();
    }

    function test_CustomerEntitlement() public view {
        bool isEntitled = customerRegistry.isEntitled(bankUser, CustomerRegistry.LicenseTier.Institutional);
        assertTrue(isEntitled);

        bool retailEntitled = customerRegistry.isEntitled(retailUser, CustomerRegistry.LicenseTier.Standard);
        assertFalse(retailEntitled);
    }

    function test_FeatureEntitlementCheck() public view {
        bytes32 fidCompliance = keccak256("FEATURE_COMPLIANCE_API");

        (bool allowedBank, string memory reasonBank) = licenseRegistry.isFeatureAllowed(bankUser, fidCompliance);
        assertTrue(allowedBank);
        assertEq(reasonBank, "Authorized");

        (bool allowedRetail, string memory reasonRetail) = licenseRegistry.isFeatureAllowed(retailUser, fidCompliance);
        assertFalse(allowedRetail);
        assertEq(reasonRetail, "Insufficient license tier");
    }
}
