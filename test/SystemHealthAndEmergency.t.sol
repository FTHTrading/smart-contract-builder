// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/health/SystemHealthRegistry.sol";
import "../contracts/emergency/EmergencyControlRegistry.sol";
import "../contracts/lineage/DataLineageRegistry.sol";

contract SystemHealthAndEmergencyTest is Test {
    SystemHealthRegistry public healthRegistry;
    EmergencyControlRegistry public emergencyRegistry;
    DataLineageRegistry public lineageRegistry;

    address public admin = address(1);

    function setUp() public {
        vm.startPrank(admin);
        healthRegistry = new SystemHealthRegistry(admin);
        emergencyRegistry = new EmergencyControlRegistry(admin);
        lineageRegistry = new DataLineageRegistry(admin);
        vm.stopPrank();
    }

    function test_HealthMetrics_Defaults() public view {
        (
            uint256 settlements,
            uint256 failed,
            uint256 reserveBps,
            uint256 lcrBps,
            uint256 updatedAt,
            bool healthy
        ) = healthRegistry.currentMetrics();

        assertEq(failed, 0);
        assertEq(reserveBps, 10000);
        assertTrue(healthy);
    }

    function test_TriggerEmergencyPause() public {
        vm.startPrank(admin);
        emergencyRegistry.triggerEmergencyPause("Disaster recovery drill");
        assertTrue(emergencyRegistry.paused());

        emergencyRegistry.triggerEmergencyUnpause();
        assertFalse(emergencyRegistry.paused());
        vm.stopPrank();
    }

    function test_RecordDataLineage() public {
        bytes32 dataHash = keccak256("NAV_REPORT_BUIDL_AUG2026");

        vm.prank(admin);
        lineageRegistry.recordDataLineage(
            dataHash,
            "BlackRock BUIDL NAV Aug 2026",
            "Chainlink + Deloitte Auditor",
            address(0x999),
            bytes32(0)
        );

        DataLineageRegistry.DataLineageRecord memory rec = lineageRegistry.getLineage(dataHash);
        assertEq(rec.oracleSource, "Chainlink + Deloitte Auditor");
        assertTrue(rec.active);
    }
}
