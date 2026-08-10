// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/treasury/NAVOracle.sol";
import "../contracts/treasury/FundAdministration.sol";

contract FundAdministrationAndNAVTest is Test {
    NAVOracle public navOracle;
    FundAdministration public fundAdmin;

    address public admin = address(1);
    address public auditor = address(0x99);

    function setUp() public {
        vm.startPrank(admin);
        navOracle = new NAVOracle(admin);
        fundAdmin = new FundAdministration(admin);
        vm.stopPrank();
    }

    function test_DefaultFund_BUIDL() public view {
        bytes32 buidlId = keccak256("BLACKROCK_BUIDL_FUND");
        FundAdministration.Fund memory f = fundAdmin.getFund(buidlId);

        assertEq(f.name, "BlackRock USD Institutional Digital Liquidity Fund");
        assertEq(f.symbol, "BUIDL");
        assertEq(uint256(f.fundType), uint256(FundAdministration.FundType.TreasuryFund));
        assertEq(f.totalAUMUSD, 500_000_000 * 1e18);
    }

    function test_NAVOracle_UpdateAndGet() public {
        bytes32 fundId = keccak256("BLACKROCK_BUIDL_FUND");

        vm.prank(admin);
        navOracle.updateNAV(
            fundId,
            1.00 * 1e18, // NAV per share $1.00
            500_000_000 * 1e18,
            0,
            auditor,
            keccak256("ATTESTATION_DOC_1")
        );

        NAVOracle.NAVReport memory report = navOracle.getNAV(fundId, 1 days);
        assertEq(report.navPerShareUSD, 1.00 * 1e18);
        assertEq(report.auditor, auditor);
    }
}
