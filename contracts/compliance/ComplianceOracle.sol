// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IIdentityRegistry {
    function isVerified(address account) external view returns (bool);
    function isAccredited(address account) external view returns (bool);
    function isInstitutional(address account) external view returns (bool);
    function jurisdictionOf(address account) external view returns (string memory);
}

interface ISanctionsRegistry {
    function isSanctioned(address account) external view returns (bool);
}

interface IJurisdictionManager {
    function validateJurisdiction(
        string calldata code,
        bool accredited,
        bool institutional
    ) external view returns (bool);
}

/**
 * @title ComplianceOracle
 * @notice Centralized compliance decision engine for transfers, mints, and redemptions.
 */
contract ComplianceOracle is AccessControl, Pausable {
    bytes32 public constant COMPLIANCE_ADMIN_ROLE = keccak256("COMPLIANCE_ADMIN_ROLE");

    struct ComplianceStatus {
        bool approved;
        bool sanctioned;
        bool restricted;
        uint256 lastUpdated;
    }

    IIdentityRegistry public identityRegistry;
    ISanctionsRegistry public sanctionsRegistry;
    IJurisdictionManager public jurisdictionManager;

    event ComplianceValidated(address indexed account, bool approved);
    event RegistriesUpdated(address identityRegistry, address sanctionsRegistry, address jurisdictionManager);

    constructor(
        address identityRegistry_,
        address sanctionsRegistry_,
        address jurisdictionManager_,
        address admin
    ) {
        require(identityRegistry_ != address(0), "Invalid identity registry");
        require(sanctionsRegistry_ != address(0), "Invalid sanctions registry");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ADMIN_ROLE, admin);

        identityRegistry = IIdentityRegistry(identityRegistry_);
        sanctionsRegistry = ISanctionsRegistry(sanctionsRegistry_);
        if (jurisdictionManager_ != address(0)) {
            jurisdictionManager = IJurisdictionManager(jurisdictionManager_);
        }
    }

    function setRegistries(
        address identityRegistry_,
        address sanctionsRegistry_,
        address jurisdictionManager_
    ) external onlyRole(COMPLIANCE_ADMIN_ROLE) {
        identityRegistry = IIdentityRegistry(identityRegistry_);
        sanctionsRegistry = ISanctionsRegistry(sanctionsRegistry_);
        jurisdictionManager = IJurisdictionManager(jurisdictionManager_);

        emit RegistriesUpdated(identityRegistry_, sanctionsRegistry_, jurisdictionManager_);
    }

    function validateInvestor(address investor) public view returns (bool) {
        if (paused()) return false;
        if (sanctionsRegistry.isSanctioned(investor)) return false;
        if (!identityRegistry.isVerified(investor)) return false;

        if (address(jurisdictionManager) != address(0)) {
            string memory jurisdiction = identityRegistry.jurisdictionOf(investor);
            bool accredited = identityRegistry.isAccredited(investor);
            bool institutional = identityRegistry.isInstitutional(investor);

            if (!jurisdictionManager.validateJurisdiction(jurisdiction, accredited, institutional)) {
                return false;
            }
        }

        return true;
    }

    function validateTransfer(
        address from,
        address to,
        uint256 /* amount */
    ) external view returns (bool) {
        return validateInvestor(from) && validateInvestor(to);
    }

    function validateMint(address recipient) external view returns (bool) {
        return validateInvestor(recipient);
    }

    function validateRedemption(address holder) external view returns (bool) {
        return validateInvestor(holder);
    }

    function getComplianceStatus(address account) external view returns (ComplianceStatus memory) {
        bool sanctioned = sanctionsRegistry.isSanctioned(account);
        bool approved = validateInvestor(account);

        return ComplianceStatus({
            approved: approved,
            sanctioned: sanctioned,
            restricted: !approved,
            lastUpdated: block.timestamp
        });
    }

    function pause() external onlyRole(COMPLIANCE_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(COMPLIANCE_ADMIN_ROLE) {
        _unpause();
    }
}
