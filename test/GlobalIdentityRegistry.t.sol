// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/compliance/GlobalIdentityRegistry.sol";

contract GlobalIdentityRegistryTest is Test {
    GlobalIdentityRegistry public globalIdRegistry;
    address public admin = address(1);
    address public unykorn = address(0x7777);

    function setUp() public {
        vm.prank(admin);
        globalIdRegistry = new GlobalIdentityRegistry(admin);
    }

    function test_DefaultIdentity_Unykorn() public view {
        (
            bytes32 id,
            string memory legalName,
            string memory lei,
            string memory bic,
            string memory jurisdiction,
            GlobalIdentityRegistry.InvestorClass iClass,
            GlobalIdentityRegistry.RiskLevel rLevel,
            bool kyc,
            bool kyb,
            bool accredited,
            bool institutional,
            bool sanctions,
            bool travel,
            uint256 expiry,
            bool active
        ) = globalIdRegistry.identities(unykorn);

        assertEq(legalName, "Unykorn LLC");
        assertEq(lei, "2549008J7LUHSQ73SI26");
        assertEq(bic, "UBECUS33XXX");
        assertEq(jurisdiction, "US");
        assertTrue(kyc);
        assertTrue(kyb);
        assertTrue(accredited);
        assertTrue(institutional);
        assertTrue(active);
    }

    function test_RegisterInstitutionalIdentity() public {
        address blackrock = address(0x9999);

        vm.prank(admin);
        globalIdRegistry.registerInstitutionalIdentity(
            blackrock,
            keccak256("BLACKROCK"),
            "BlackRock Inc.",
            "5493001KJTIIGC8Y1R12",
            "BLKUS33XXX",
            "US",
            GlobalIdentityRegistry.InvestorClass.Institutional,
            GlobalIdentityRegistry.RiskLevel.Low,
            true,
            true,
            true,
            true,
            3650 days
        );

        assertTrue(globalIdRegistry.isVerified(blackrock));
        assertTrue(globalIdRegistry.isInstitutional(blackrock));
    }
}
