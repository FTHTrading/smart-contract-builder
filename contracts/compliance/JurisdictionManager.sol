// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title JurisdictionManager
 * @notice Regional policy and jurisdiction restrictions engine for regulated asset offerings.
 */
contract JurisdictionManager is AccessControl, Pausable {
    bytes32 public constant JURISDICTION_ADMIN_ROLE = keccak256("JURISDICTION_ADMIN_ROLE");

    struct Jurisdiction {
        string code;
        string name;
        bool allowed;
        bool accreditedOnly;
        bool institutionalOnly;
        bool active;
    }

    mapping(bytes32 => Jurisdiction) private jurisdictions;
    bytes32[] private jurisdictionList;

    event JurisdictionAdded(string code, string name);
    event JurisdictionUpdated(string code, bool allowed, bool accreditedOnly, bool institutionalOnly, bool active);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(JURISDICTION_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function addJurisdiction(
        string calldata code,
        string calldata name,
        bool allowed,
        bool accreditedOnly,
        bool institutionalOnly
    ) external onlyRole(JURISDICTION_ADMIN_ROLE) {
        bytes32 key = _key(code);
        require(bytes(jurisdictions[key].code).length == 0, "Jurisdiction exists");

        jurisdictions[key] = Jurisdiction({
            code: code,
            name: name,
            allowed: allowed,
            accreditedOnly: accreditedOnly,
            institutionalOnly: institutionalOnly,
            active: true
        });

        jurisdictionList.push(key);
        emit JurisdictionAdded(code, name);
    }

    function updateJurisdiction(
        string calldata code,
        bool allowed,
        bool accreditedOnly,
        bool institutionalOnly,
        bool active
    ) external onlyRole(JURISDICTION_ADMIN_ROLE) {
        bytes32 key = _key(code);
        require(bytes(jurisdictions[key].code).length > 0, "Unknown jurisdiction");

        Jurisdiction storage j = jurisdictions[key];
        j.allowed = allowed;
        j.accreditedOnly = accreditedOnly;
        j.institutionalOnly = institutionalOnly;
        j.active = active;

        emit JurisdictionUpdated(code, allowed, accreditedOnly, institutionalOnly, active);
    }

    function validateJurisdiction(
        string calldata code,
        bool accredited,
        bool institutional
    ) external view returns (bool) {
        Jurisdiction memory j = jurisdictions[_key(code)];

        if (!j.active || !j.allowed) {
            return false;
        }

        if (j.accreditedOnly && !accredited) {
            return false;
        }

        if (j.institutionalOnly && !institutional) {
            return false;
        }

        return true;
    }

    function isAllowed(string calldata code) external view returns (bool) {
        Jurisdiction memory j = jurisdictions[_key(code)];
        return j.active && j.allowed;
    }

    function getJurisdiction(string calldata code) external view returns (Jurisdiction memory) {
        return jurisdictions[_key(code)];
    }

    function pause() external onlyRole(JURISDICTION_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(JURISDICTION_ADMIN_ROLE) {
        _unpause();
    }

    function _key(string memory code) internal pure returns (bytes32) {
        return keccak256(bytes(code));
    }

    function _initializeDefaults() internal {
        _addDefault("US", "United States", true, false, false);
        _addDefault("EU", "European Union", true, false, false);
        _addDefault("UK", "United Kingdom", true, false, false);
        _addDefault("AE", "United Arab Emirates", true, false, false);
        _addDefault("SG", "Singapore", true, false, false);
        _addDefault("HK", "Hong Kong", true, false, false);
        _addDefault("CA", "Canada", true, false, false);
    }

    function _addDefault(
        string memory code,
        string memory name,
        bool allowed,
        bool accreditedOnly,
        bool institutionalOnly
    ) internal {
        bytes32 key = _key(code);
        jurisdictions[key] = Jurisdiction({
            code: code,
            name: name,
            allowed: allowed,
            accreditedOnly: accreditedOnly,
            institutionalOnly: institutionalOnly,
            active: true
        });
        jurisdictionList.push(key);
    }
}
