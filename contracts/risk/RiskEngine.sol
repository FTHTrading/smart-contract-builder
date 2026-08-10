// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RiskEngine
 * @notice Enterprise Risk Management Engine tracking Counterparty Risk, Jurisdiction Risk, Custodian Risk, Concentration Risk, and Liquidity Risk.
 */
contract RiskEngine is AccessControl {
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");

    enum RiskLevel {
        Low,
        Medium,
        High,
        Restricted
    }

    struct RiskProfile {
        string entityOrAsset;
        RiskLevel counterpartyRisk;
        RiskLevel jurisdictionRisk;
        RiskLevel custodianRisk;
        uint16 concentrationCapBps; // Max portfolio allocation in basis points (e.g. 4000 = 40%)
        uint256 lastEvaluatedAt;
        bool active;
    }

    // entityOrAsset => RiskProfile
    mapping(string => RiskProfile) public riskProfiles;

    event RiskEvaluated(string indexed entityOrAsset, RiskLevel counterpartyRisk, RiskLevel jurisdictionRisk, uint16 concentrationCapBps);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RISK_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function evaluateRisk(
        string calldata entityOrAsset,
        RiskLevel counterpartyRisk,
        RiskLevel jurisdictionRisk,
        RiskLevel custodianRisk,
        uint16 concentrationCapBps
    ) external onlyRole(RISK_ADMIN_ROLE) {
        riskProfiles[entityOrAsset] = RiskProfile({
            entityOrAsset: entityOrAsset,
            counterpartyRisk: counterpartyRisk,
            jurisdictionRisk: jurisdictionRisk,
            custodianRisk: custodianRisk,
            concentrationCapBps: concentrationCapBps,
            lastEvaluatedAt: block.timestamp,
            active: true
        });

        emit RiskEvaluated(entityOrAsset, counterpartyRisk, jurisdictionRisk, concentrationCapBps);
    }

    function checkConcentrationRisk(string calldata entityOrAsset, uint16 currentAllocationBps) external view returns (bool warning, string memory reason) {
        RiskProfile memory p = riskProfiles[entityOrAsset];
        if (!p.active) return (true, "Risk profile uninitialized");
        if (currentAllocationBps > p.concentrationCapBps) {
            return (true, "Concentration cap exceeded");
        }
        return (false, "Risk within tolerance");
    }

    function _initializeDefaults() internal {
        _addProfile("USDC", RiskLevel.Low, RiskLevel.Low, RiskLevel.Low, 5000);
        _addProfile("USDF", RiskLevel.Low, RiskLevel.Low, RiskLevel.Low, 5000);
        _addProfile("BUIDL", RiskLevel.Low, RiskLevel.Low, RiskLevel.Low, 4000);
        _addProfile("BENJI", RiskLevel.Low, RiskLevel.Low, RiskLevel.Low, 4000);
        _addProfile("USDY", RiskLevel.Medium, RiskLevel.Low, RiskLevel.Medium, 3000);
    }

    function _addProfile(string memory name, RiskLevel cp, RiskLevel jur, RiskLevel cust, uint16 capBps) internal {
        riskProfiles[name] = RiskProfile({
            entityOrAsset: name,
            counterpartyRisk: cp,
            jurisdictionRisk: jur,
            custodianRisk: cust,
            concentrationCapBps: capBps,
            lastEvaluatedAt: block.timestamp,
            active: true
        });
    }
}
