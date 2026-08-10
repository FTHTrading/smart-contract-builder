// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ContractRegistry
 * @notice System-wide Contract Lifecycle, Version Management, and Dependency Registry tracking active implementation deployments across layers.
 */
contract ContractRegistry is AccessControl {
    bytes32 public constant CORE_ADMIN_ROLE = keccak256("CORE_ADMIN_ROLE");

    struct ContractVersion {
        string contractName;
        uint16 majorVersion;
        uint16 minorVersion;
        uint16 patchVersion;
        address implementationAddress;
        string gitCommitHash;
        uint256 deployedAt;
        bool active;
        bool deprecated;
    }

    // contractName => ContractVersion
    mapping(string => ContractVersion) public registry;
    string[] public registeredNames;

    event ContractRegistered(string contractName, address indexed implementationAddress, uint16 major, uint16 minor, uint16 patch);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CORE_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerContractVersion(
        string calldata contractName,
        uint16 majorVersion,
        uint16 minorVersion,
        uint16 patchVersion,
        address implementationAddress,
        string calldata gitCommitHash
    ) external onlyRole(CORE_ADMIN_ROLE) {
        if (registry[contractName].implementationAddress == address(0)) {
            registeredNames.push(contractName);
        }

        registry[contractName] = ContractVersion({
            contractName: contractName,
            majorVersion: majorVersion,
            minorVersion: minorVersion,
            patchVersion: patchVersion,
            implementationAddress: implementationAddress,
            gitCommitHash: gitCommitHash,
            deployedAt: block.timestamp,
            active: true,
            deprecated: false
        });

        emit ContractRegistered(contractName, implementationAddress, majorVersion, minorVersion, patchVersion);
    }

    function getContract(string calldata contractName) external view returns (ContractVersion memory) {
        return registry[contractName];
    }

    function _initializeDefaults() internal {
        _addDefault("MultiChainRegistry", 1, 1, 0, address(0x1001), "1ecc09c");
        _addDefault("GlobalIdentityRegistry", 1, 0, 0, address(0x1002), "1ecc09c");
        _addDefault("ComplianceOracle", 1, 0, 0, address(0x1003), "1ecc09c");
        _addDefault("RegulatoryFrameworkRegistry", 1, 0, 0, address(0x1004), "1ecc09c");
        _addDefault("TreasuryLedger", 1, 0, 0, address(0x1005), "1ecc09c");
        _addDefault("YieldRouter", 1, 0, 0, address(0x1006), "1ecc09c");
    }

    function _addDefault(string memory cName, uint16 maj, uint16 min, uint16 pat, address impl, string memory gitHash) internal {
        registry[cName] = ContractVersion({
            contractName: cName,
            majorVersion: maj,
            minorVersion: min,
            patchVersion: pat,
            implementationAddress: impl,
            gitCommitHash: gitHash,
            deployedAt: block.timestamp,
            active: true,
            deprecated: false
        });
        registeredNames.push(cName);
    }
}
