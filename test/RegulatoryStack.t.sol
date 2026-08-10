// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/regulatory/RegulatoryFrameworkRegistry.sol";

contract RegulatoryStackTest is Test {
    RegulatoryFrameworkRegistry public regRegistry;
    address public admin = address(1);

    function setUp() public {
        vm.prank(admin);
        regRegistry = new RegulatoryFrameworkRegistry(admin);
    }

    function test_DefaultFramework_GENIUS() public view {
        RegulatoryFrameworkRegistry.RegulatoryFramework memory genius = regRegistry.getFramework("GENIUS");
        assertEq(genius.name, "GENIUS Act");
        assertEq(genius.jurisdiction, "US");
        assertTrue(genius.requiresKYC);
        assertTrue(genius.requiresTravelRule);
    }

    function test_DefaultFramework_MICA() public view {
        RegulatoryFrameworkRegistry.RegulatoryFramework memory mica = regRegistry.getFramework("MICA");
        assertEq(mica.name, "Markets in Crypto Assets");
        assertEq(mica.jurisdiction, "EU");
        assertTrue(mica.requiresAML);
    }

    function test_BindAssetToFramework() public {
        vm.startPrank(admin);
        regRegistry.bindAssetToFramework("USDC", "GENIUS");
        regRegistry.bindAssetToFramework("USDC", "MICA");
        vm.stopPrank();

        bytes32[] memory frameworks = regRegistry.getAssetFrameworks("USDC");
        assertEq(frameworks.length, 2);
    }

    function test_IsCompliantInvestor() public view {
        bool compliant = regRegistry.isCompliantInvestor(
            "GENIUS",
            true, // kyc
            true, // kyb
            true, // aml
            true, // travel rule
            RegulatoryFrameworkRegistry.InvestorClass.Retail
        );
        assertTrue(compliant);
    }
}
