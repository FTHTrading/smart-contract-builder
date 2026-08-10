// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/risk/RiskEngine.sol";
import "../contracts/documents/DocumentRegistry.sol";

contract RiskEngineAndDocumentsTest is Test {
    RiskEngine public riskEngine;
    DocumentRegistry public documentRegistry;

    address public admin = address(1);

    function setUp() public {
        vm.startPrank(admin);
        riskEngine = new RiskEngine(admin);
        documentRegistry = new DocumentRegistry(admin);
        vm.stopPrank();
    }

    function test_DefaultRiskProfile_BUIDL() public view {
        (
            string memory name,
            RiskEngine.RiskLevel cp,
            RiskEngine.RiskLevel jur,
            RiskEngine.RiskLevel cust,
            uint16 capBps,
            uint256 evaluatedAt,
            bool active
        ) = riskEngine.riskProfiles("BUIDL");

        assertEq(name, "BUIDL");
        assertEq(uint256(cp), uint256(RiskEngine.RiskLevel.Low));
        assertEq(capBps, 4000); // 40% cap
        assertTrue(active);
    }

    function test_ConcentrationRiskWarning() public view {
        (bool warning, string memory reason) = riskEngine.checkConcentrationRisk("BUIDL", 4500); // 45% > 40%
        assertTrue(warning);
        assertEq(reason, "Concentration cap exceeded");
    }

    function test_DefaultDocument_Unykorn() public view {
        bytes32[] memory docIds = documentRegistry.getDocumentsForSymbol("UNYKORN");
        assertEq(docIds.length, 1);

        (
            bytes32 docId,
            string memory symbol,
            DocumentRegistry.DocumentCategory category,
            string memory title,
            bytes32 shaHash,
            string memory uri,
            uint256 ts,
            address uploader,
            bool active
        ) = documentRegistry.documents(docIds[0]);

        assertEq(symbol, "UNYKORN");
        assertEq(title, "Unykorn LLC Corporate Resolution & Asset Governance July 2026");
        assertTrue(active);
    }
}
