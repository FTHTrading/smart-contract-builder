// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ATP7332Registry
 * @notice Apostle Chain (ATP 7332) Sovereign Root Namespace Registry for 78 Genesis Suffix Roots and 60 Athlete Trust Namespaces.
 */
contract ATP7332Registry is AccessControl {
    bytes32 public constant ROOT_REGISTRAR_ROLE = keccak256("ROOT_REGISTRAR_ROLE");

    struct SovereignRoot {
        string suffix;        // e.g. ".unykorn", ".troptions", ".athlete"
        bytes32 genesisHash;  // Cryptographic genesis anchor
        address owner;
        uint256 registeredAt;
        bool isGenesisRoot;
        bool active;
    }

    // suffix => SovereignRoot
    mapping(string => SovereignRoot) public roots;
    string[] public registeredSuffixes;

    event SovereignRootRegistered(string indexed suffix, bytes32 indexed genesisHash, address indexed owner, bool isGenesis);
    event SovereignRootUpdated(string indexed suffix, address indexed newOwner, bool active);

    error SuffixAlreadyRegistered(string suffix);
    error SuffixNotFound(string suffix);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ROOT_REGISTRAR_ROLE, admin);
    }

    function registerSovereignRoot(
        string calldata suffix,
        bytes32 genesisHash,
        address owner,
        bool isGenesis
    ) external onlyRole(ROOT_REGISTRAR_ROLE) {
        if (roots[suffix].active) revert SuffixAlreadyRegistered(suffix);

        roots[suffix] = SovereignRoot({
            suffix: suffix,
            genesisHash: genesisHash,
            owner: owner,
            registeredAt: block.timestamp,
            isGenesisRoot: isGenesis,
            active: true
        });

        registeredSuffixes.push(suffix);
        emit SovereignRootRegistered(suffix, genesisHash, owner, isGenesis);
    }

    function updateSovereignRootOwner(
        string calldata suffix,
        address newOwner,
        bool activeStatus
    ) external onlyRole(ROOT_REGISTRAR_ROLE) {
        if (!roots[suffix].active) revert SuffixNotFound(suffix);

        roots[suffix].owner = newOwner;
        roots[suffix].active = activeStatus;

        emit SovereignRootUpdated(suffix, newOwner, activeStatus);
    }

    function getRegisteredSuffixesCount() external view returns (uint256) {
        return registeredSuffixes.length;
    }
}
