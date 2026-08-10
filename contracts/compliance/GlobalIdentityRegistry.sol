// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title GlobalIdentityRegistry
 * @notice Institutional Identity Registry integrating Legal Entity Identifiers (LEI), BICs, ISO20022 profiles, FATF risk scores, and investor classifications.
 */
contract GlobalIdentityRegistry is AccessControl {
    bytes32 public constant IDENTITY_VERIFIER_ROLE = keccak256("IDENTITY_VERIFIER_ROLE");

    enum InvestorClass {
        Retail,
        Qualified,
        Accredited,
        Professional,
        Institutional
    }

    enum RiskLevel {
        Low,
        Medium,
        High,
        Restricted
    }

    struct ISO20022Profile {
        string bic;
        string lei;
        string institutionName;
        string countryCode;
        bool active;
    }

    struct InstitutionalIdentity {
        bytes32 id;
        string legalName;
        string lei;
        string bic;
        string jurisdiction;
        InvestorClass investorClass;
        RiskLevel riskLevel;
        bool kycVerified;
        bool kybVerified;
        bool accredited;
        bool institutional;
        bool sanctionsScreened;
        bool travelRuleCompliant;
        uint256 expiry;
        bool active;
    }

    // account => InstitutionalIdentity
    mapping(address => InstitutionalIdentity) public identities;

    event InstitutionalIdentityRegistered(address indexed account, string legalName, string lei, string jurisdiction);
    event IdentityRiskLevelUpdated(address indexed account, RiskLevel riskLevel);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(IDENTITY_VERIFIER_ROLE, admin);

        _initializeDefaults();
    }

    function registerInstitutionalIdentity(
        address account,
        bytes32 id,
        string calldata legalName,
        string calldata lei,
        string calldata bic,
        string calldata jurisdiction,
        InvestorClass investorClass,
        RiskLevel riskLevel,
        bool kyc,
        bool kyb,
        bool accredited,
        bool institutional,
        uint256 expiryDuration
    ) external onlyRole(IDENTITY_VERIFIER_ROLE) {
        identities[account] = InstitutionalIdentity({
            id: id,
            legalName: legalName,
            lei: lei,
            bic: bic,
            jurisdiction: jurisdiction,
            investorClass: investorClass,
            riskLevel: riskLevel,
            kycVerified: kyc,
            kybVerified: kyb,
            accredited: accredited,
            institutional: institutional,
            sanctionsScreened: true,
            travelRuleCompliant: true,
            expiry: block.timestamp + expiryDuration,
            active: true
        });

        emit InstitutionalIdentityRegistered(account, legalName, lei, jurisdiction);
    }

    function updateRiskLevel(address account, RiskLevel newRiskLevel) external onlyRole(IDENTITY_VERIFIER_ROLE) {
        identities[account].riskLevel = newRiskLevel;
        emit IdentityRiskLevelUpdated(account, newRiskLevel);
    }

    function isVerified(address account) external view returns (bool) {
        InstitutionalIdentity memory id = identities[account];
        return id.active && (id.kycVerified || id.kybVerified) && block.timestamp < id.expiry && id.riskLevel != RiskLevel.Restricted;
    }

    function isAccredited(address account) external view returns (bool) {
        InstitutionalIdentity memory id = identities[account];
        return id.active && id.accredited && block.timestamp < id.expiry;
    }

    function isInstitutional(address account) external view returns (bool) {
        InstitutionalIdentity memory id = identities[account];
        return id.active && id.institutional && block.timestamp < id.expiry;
    }

    function _initializeDefaults() internal {
        // Unykorn LLC (Wyoming EIN 42-3536633, GLEIF LEI 2549008J7LUHSQ73SI26)
        identities[address(0x7777)] = InstitutionalIdentity({
            id: keccak256("UNYKORN_LLC"),
            legalName: "Unykorn LLC",
            lei: "2549008J7LUHSQ73SI26",
            bic: "UBECUS33XXX",
            jurisdiction: "US",
            investorClass: InvestorClass.Institutional,
            riskLevel: RiskLevel.Low,
            kycVerified: true,
            kybVerified: true,
            accredited: true,
            institutional: true,
            sanctionsScreened: true,
            travelRuleCompliant: true,
            expiry: block.timestamp + 3650 days,
            active: true
        });
    }
}
