// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./CustomerRegistry.sol";

/**
 * @title LicenseRegistry
 * @notice Entitlement Engine managing feature flags, API quotas, and capability entitlements per customer tier.
 */
contract LicenseRegistry is AccessControl {
    bytes32 public constant LICENSE_MANAGER_ROLE = keccak256("LICENSE_MANAGER_ROLE");

    CustomerRegistry public immutable customerRegistry;

    struct FeatureEntitlement {
        bytes32 featureId;
        string featureName;
        CustomerRegistry.LicenseTier minRequiredTier;
        uint256 monthlyQuota;
        bool active;
    }

    mapping(bytes32 => FeatureEntitlement) public features;

    event FeatureConfigured(bytes32 indexed featureId, string featureName, CustomerRegistry.LicenseTier minRequiredTier, uint256 monthlyQuota);

    constructor(address _customerRegistry, address admin) {
        customerRegistry = CustomerRegistry(_customerRegistry);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LICENSE_MANAGER_ROLE, admin);

        _configureDefaultFeatures();
    }

    function _configureDefaultFeatures() internal {
        bytes32 fidIdentity = keccak256("FEATURE_IDENTITY_ORACLE");
        bytes32 fidCompliance = keccak256("FEATURE_COMPLIANCE_API");
        bytes32 fidTreasury = keccak256("FEATURE_TREASURY_LEDGER");
        bytes32 fidDeployer = keccak256("FEATURE_AUTONOMOUS_DEPLOYER");

        features[fidIdentity] = FeatureEntitlement(fidIdentity, "Identity Oracle API", CustomerRegistry.LicenseTier.Standard, 10000, true);
        features[fidCompliance] = FeatureEntitlement(fidCompliance, "Compliance-as-a-Service", CustomerRegistry.LicenseTier.Institutional, 50000, true);
        features[fidTreasury] = FeatureEntitlement(fidTreasury, "Treasury General Ledger & Yield", CustomerRegistry.LicenseTier.Institutional, 100000, true);
        features[fidDeployer] = FeatureEntitlement(fidDeployer, "Autonomous Canton & Multi-Chain Deployer", CustomerRegistry.LicenseTier.SovereignEnterprise, 999999, true);
    }

    function configureFeature(
        bytes32 featureId,
        string calldata featureName,
        CustomerRegistry.LicenseTier minRequiredTier,
        uint256 monthlyQuota
    ) external onlyRole(LICENSE_MANAGER_ROLE) {
        features[featureId] = FeatureEntitlement(featureId, featureName, minRequiredTier, monthlyQuota, true);
        emit FeatureConfigured(featureId, featureName, minRequiredTier, monthlyQuota);
    }

    function isFeatureAllowed(address account, bytes32 featureId) external view returns (bool allowed, string memory reason) {
        FeatureEntitlement memory f = features[featureId];
        if (!f.active) return (false, "Feature inactive");

        bool entitled = customerRegistry.isEntitled(account, f.minRequiredTier);
        if (!entitled) return (false, "Insufficient license tier");

        return (true, "Authorized");
    }
}
