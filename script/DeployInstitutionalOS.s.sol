// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/compliance/GlobalIdentityRegistry.sol";
import "../contracts/compliance/SanctionsRegistry.sol";
import "../contracts/compliance/JurisdictionManager.sol";
import "../contracts/compliance/ComplianceOracle.sol";
import "../contracts/regulatory/RegulatoryFrameworkRegistry.sol";
import "../contracts/registries/CantonParticipantRegistry.sol";
import "../contracts/registries/MultiChainRegistry.sol";
import "../contracts/registries/RWARegistry.sol";
import "../contracts/custody/CustodyRegistry.sol";
import "../contracts/oracle/ValuationOracle.sol";
import "../contracts/treasury/NAVOracle.sol";
import "../contracts/payments/PaymentRailRegistry.sol";
import "../contracts/settlement/StablecoinSettlementHub.sol";
import "../contracts/treasury/TreasuryPolicyEngine.sol";
import "../contracts/vaults/YieldRouter.sol";
import "../contracts/ledger/TreasuryLedger.sol";
import "../contracts/access/GlobalRoleRegistry.sol";
import "../contracts/audit/AuditRegistry.sol";
import "../contracts/governance/GovernanceRegistry.sol";
import "../contracts/risk/RiskEngine.sol";
import "../contracts/documents/DocumentRegistry.sol";
import "../contracts/core/ContractRegistry.sol";
import "../contracts/workflow/WorkflowEngine.sol";
import "../contracts/policy/PolicyEngine.sol";
import "../contracts/health/SystemHealthRegistry.sol";
import "../contracts/emergency/EmergencyControlRegistry.sol";
import "../contracts/lineage/DataLineageRegistry.sol";

contract DeployInstitutionalOS is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying 13-Layer Institutional Operating System from:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Identity & Compliance Layer
        GlobalIdentityRegistry globalId = new GlobalIdentityRegistry(deployer);
        SanctionsRegistry sanctions = new SanctionsRegistry(deployer);
        JurisdictionManager jurisdiction = new JurisdictionManager(deployer);
        ComplianceOracle oracle = new ComplianceOracle(address(globalId), address(sanctions), address(jurisdiction), deployer);

        // 2. Regulatory & Participant Layer
        RegulatoryFrameworkRegistry regFramework = new RegulatoryFrameworkRegistry(deployer);
        CantonParticipantRegistry cantonReg = new CantonParticipantRegistry(deployer);

        // 3. Asset & Custody Layer
        MultiChainRegistry multiChainReg = new MultiChainRegistry(deployer);
        RWARegistry rwaReg = new RWARegistry(deployer);
        CustodyRegistry custodyReg = new CustodyRegistry(deployer);

        // 4. Valuation & Settlement Layer
        ValuationOracle valOracle = new ValuationOracle(deployer);
        NAVOracle navOracle = new NAVOracle(deployer);
        PaymentRailRegistry railReg = new PaymentRailRegistry(deployer);
        StablecoinSettlementHub settlementHub = new StablecoinSettlementHub(deployer);

        // 5. Treasury & Accounting Layer
        TreasuryPolicyEngine policyEngineTreasury = new TreasuryPolicyEngine(deployer);
        TreasuryLedger ledger = new TreasuryLedger(deployer);

        // 6. Roles & Auditability
        GlobalRoleRegistry roles = new GlobalRoleRegistry(deployer);
        AuditRegistry audit = new AuditRegistry(deployer);
        GovernanceRegistry gov = new GovernanceRegistry(deployer);

        // 7. Cross-Cutting Operating Platform Suite
        RiskEngine risk = new RiskEngine(deployer);
        DocumentRegistry docReg = new DocumentRegistry(deployer);
        ContractRegistry contractReg = new ContractRegistry(deployer);
        WorkflowEngine workflow = new WorkflowEngine(deployer);
        PolicyEngine policy = new PolicyEngine(deployer);
        SystemHealthRegistry health = new SystemHealthRegistry(deployer);
        EmergencyControlRegistry emergency = new EmergencyControlRegistry(deployer);
        DataLineageRegistry lineage = new DataLineageRegistry(deployer);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("GlobalIdentityRegistry:      ", address(globalId));
        console.log("ComplianceOracle:            ", address(oracle));
        console.log("RegulatoryFrameworkRegistry: ", address(regFramework));
        console.log("MultiChainRegistry:          ", address(multiChainReg));
        console.log("TreasuryLedger:              ", address(ledger));
        console.log("WorkflowEngine:              ", address(workflow));
        console.log("ContractRegistry:            ", address(contractReg));
    }
}
