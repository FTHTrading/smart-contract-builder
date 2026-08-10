// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/ledger/TreasuryLedger.sol";
import "../contracts/oracle/ValuationOracle.sol";

contract TreasuryLedgerAndValuationTest is Test {
    TreasuryLedger public ledger;
    ValuationOracle public valuationOracle;

    address public admin = address(1);
    address public corporation = address(0x9999);

    function setUp() public {
        vm.startPrank(admin);
        ledger = new TreasuryLedger(admin);
        valuationOracle = new ValuationOracle(admin);
        vm.stopPrank();
    }

    function test_DefaultValuation_BUIDL() public view {
        ValuationOracle.AssetValuation memory v = valuationOracle.getValuation("BUIDL");

        assertEq(v.symbol, "BUIDL");
        assertEq(v.priceUSD, 1.00 * 1e18);
        assertEq(v.yieldBps, 525); // 5.25%
        assertEq(v.reserveRatioBps, 10000);
    }

    function test_PostLedgerDepositAndIncome() public {
        vm.startPrank(admin);
        ledger.postEntry(
            corporation,
            "USDC",
            TreasuryLedger.EntryType.AssetDeposit,
            1_000_000 * 1e18,
            "Circle FedNow Gateway",
            keccak256("TX_REF_1")
        );

        ledger.postEntry(
            corporation,
            "BUIDL",
            TreasuryLedger.EntryType.YieldIncome,
            4_200 * 1e18,
            "BlackRock Yield Distribution",
            keccak256("TX_REF_2")
        );
        vm.stopPrank();

        assertEq(ledger.getEntityAUM(corporation), 1_004_200 * 1e18);
        assertEq(ledger.getLedgerCount(), 2);
    }
}
