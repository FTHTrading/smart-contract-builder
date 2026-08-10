// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title SystemHealthRegistry
 * @notice Real-time system health, settlement failure, reserve coverage, and liquidity ratio observability registry.
 */
contract SystemHealthRegistry is AccessControl {
    bytes32 public constant HEALTH_ADMIN_ROLE = keccak256("HEALTH_ADMIN_ROLE");

    struct SystemHealthMetrics {
        uint256 totalSettlements24h;
        uint256 failedSettlements24h;
        uint256 averageReserveRatioBps;
        uint256 liquidityCoverageRatioBps;
        uint256 lastUpdated;
        bool systemHealthy;
    }

    SystemHealthMetrics public currentMetrics;

    event SystemHealthUpdated(uint256 failedSettlements24h, uint256 averageReserveRatioBps, bool systemHealthy);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(HEALTH_ADMIN_ROLE, admin);

        currentMetrics = SystemHealthMetrics({
            totalSettlements24h: 1250,
            failedSettlements24h: 0,
            averageReserveRatioBps: 10000, // 100% reserve
            liquidityCoverageRatioBps: 12500, // 125% LCR
            lastUpdated: block.timestamp,
            systemHealthy: true
        });
    }

    function updateHealthMetrics(
        uint256 totalSettlements24h,
        uint256 failedSettlements24h,
        uint256 averageReserveRatioBps,
        uint256 liquidityCoverageRatioBps,
        bool systemHealthy
    ) external onlyRole(HEALTH_ADMIN_ROLE) {
        currentMetrics = SystemHealthMetrics({
            totalSettlements24h: totalSettlements24h,
            failedSettlements24h: failedSettlements24h,
            averageReserveRatioBps: averageReserveRatioBps,
            liquidityCoverageRatioBps: liquidityCoverageRatioBps,
            lastUpdated: block.timestamp,
            systemHealthy: systemHealthy
        });

        emit SystemHealthUpdated(failedSettlements24h, averageReserveRatioBps, systemHealthy);
    }
}
