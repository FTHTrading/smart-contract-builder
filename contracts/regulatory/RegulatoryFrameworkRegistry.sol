// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title RegulatoryFrameworkRegistry
 * @notice Authoritative on-chain registry for global regulatory regimes, issuer obligations, investor classifications, and asset compliance mappings.
 */
contract RegulatoryFrameworkRegistry is AccessControl, Pausable {
    bytes32 public constant REGULATORY_ADMIN_ROLE = keccak256("REGULATORY_ADMIN_ROLE");

    enum FrameworkType {
        Stablecoin,
        Securities,
        Payments,
        DigitalAssets,
        Banking,
        RWA
    }

    enum InvestorClass {
        Retail,
        Qualified,
        Accredited,
        Professional,
        Institutional
    }

    struct RegulatoryFramework {
        string code;
        string name;
        string regulator;
        string jurisdiction;
        FrameworkType frameworkType;
        bool active;
        bool requiresKYC;
        bool requiresKYB;
        bool requiresAML;
        bool requiresTravelRule;
        bool reserveAttestationRequired;
        bool sanctionsScreeningRequired;
        InvestorClass minimumInvestorClass;
        string referenceURI;
    }

    mapping(bytes32 => RegulatoryFramework) private frameworks;
    bytes32[] private frameworkIds;

    // assetSymbol => frameworkCodes
    mapping(string => bytes32[]) private assetFrameworks;

    event FrameworkRegistered(string code, string name, string regulator, string jurisdiction);
    event FrameworkUpdated(string code);
    event AssetFrameworkBound(string indexed assetSymbol, string indexed frameworkCode);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGULATORY_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerFramework(RegulatoryFramework calldata framework) external onlyRole(REGULATORY_ADMIN_ROLE) {
        bytes32 key = _key(framework.code);
        require(bytes(frameworks[key].code).length == 0, "Framework exists");

        frameworks[key] = framework;
        frameworkIds.push(key);

        emit FrameworkRegistered(framework.code, framework.name, framework.regulator, framework.jurisdiction);
    }

    function bindAssetToFramework(string calldata assetSymbol, string calldata frameworkCode) external onlyRole(REGULATORY_ADMIN_ROLE) {
        bytes32 key = _key(frameworkCode);
        require(bytes(frameworks[key].code).length > 0, "Framework missing");

        assetFrameworks[assetSymbol].push(key);
        emit AssetFrameworkBound(assetSymbol, frameworkCode);
    }

    function getFramework(string calldata code) external view returns (RegulatoryFramework memory) {
        return frameworks[_key(code)];
    }

    function getAssetFrameworks(string calldata assetSymbol) external view returns (bytes32[] memory) {
        return assetFrameworks[assetSymbol];
    }

    function isCompliantInvestor(
        string calldata frameworkCode,
        bool kycVerified,
        bool kybVerified,
        bool amlApproved,
        bool travelRuleSatisfied,
        InvestorClass investorClass
    ) external view returns (bool) {
        RegulatoryFramework memory framework = frameworks[_key(frameworkCode)];

        if (!framework.active) return false;
        if (framework.requiresKYC && !kycVerified) return false;
        if (framework.requiresKYB && !kybVerified) return false;
        if (framework.requiresAML && !amlApproved) return false;
        if (framework.requiresTravelRule && !travelRuleSatisfied) return false;
        if (uint256(investorClass) < uint256(framework.minimumInvestorClass)) return false;

        return true;
    }

    function pause() external onlyRole(REGULATORY_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(REGULATORY_ADMIN_ROLE) {
        _unpause();
    }

    function _key(string memory code) internal pure returns (bytes32) {
        return keccak256(bytes(code));
    }

    function _initializeDefaults() internal {
        _registerDefault("GENIUS", "GENIUS Act", "OCC/Federal", "US", FrameworkType.Stablecoin, InvestorClass.Retail);
        _registerDefault("MICA", "Markets in Crypto Assets", "European Union", "EU", FrameworkType.Stablecoin, InvestorClass.Retail);
        _registerDefault("MAS", "Monetary Authority of Singapore", "MAS", "SG", FrameworkType.DigitalAssets, InvestorClass.Retail);
        _registerDefault("HKMA", "Hong Kong Monetary Authority", "HKMA", "HK", FrameworkType.DigitalAssets, InvestorClass.Retail);
        _registerDefault("VARA", "Virtual Assets Regulatory Authority", "VARA", "AE", FrameworkType.DigitalAssets, InvestorClass.Retail);
        _registerDefault("ADGM", "Abu Dhabi Global Market", "FSRA", "AE", FrameworkType.DigitalAssets, InvestorClass.Qualified);
        _registerDefault("FCA", "Financial Conduct Authority", "FCA", "UK", FrameworkType.DigitalAssets, InvestorClass.Retail);
        _registerDefault("FINMA", "Swiss Financial Market Supervisory Authority", "FINMA", "CH", FrameworkType.DigitalAssets, InvestorClass.Retail);
        _registerDefault("SEC", "Securities and Exchange Commission", "SEC", "US", FrameworkType.Securities, InvestorClass.Accredited);
    }

    function _registerDefault(
        string memory code,
        string memory name,
        string memory regulator,
        string memory jurisdiction,
        FrameworkType fType,
        InvestorClass minClass
    ) internal {
        bytes32 key = _key(code);
        frameworks[key] = RegulatoryFramework({
            code: code,
            name: name,
            regulator: regulator,
            jurisdiction: jurisdiction,
            frameworkType: fType,
            active: true,
            requiresKYC: true,
            requiresKYB: true,
            requiresAML: true,
            requiresTravelRule: true,
            reserveAttestationRequired: true,
            sanctionsScreeningRequired: true,
            minimumInvestorClass: minClass,
            referenceURI: ""
        });
        frameworkIds.push(key);
    }
}
