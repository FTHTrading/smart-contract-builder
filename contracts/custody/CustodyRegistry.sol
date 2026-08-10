// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CustodyRegistry
 * @notice Global Custody Ownership & Attestation Mapping linking assets to qualified custodians (Circle, BNY Mellon, Franklin Transfer Agent, BitGo, Anchorage, Fireblocks).
 */
contract CustodyRegistry is AccessControl {
    bytes32 public constant CUSTODY_ADMIN_ROLE = keccak256("CUSTODY_ADMIN_ROLE");

    struct CustodyMapping {
        string assetSymbol;
        string custodianName;
        address custodianAddress;
        address auditorAddress;
        address insuranceProvider;
        uint256 reserveRatioBps; // 10000 = 100%
        uint256 lastAttestationDate;
        bytes32 attestationHash;
        bool active;
    }

    // assetSymbol => CustodyMapping
    mapping(string => CustodyMapping) public custodyMappings;
    string[] public assetSymbols;

    event CustodyMapped(string indexed assetSymbol, string custodianName, address indexed custodianAddress, uint256 reserveRatioBps);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CUSTODY_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function setCustodyMapping(
        string calldata assetSymbol,
        string calldata custodianName,
        address custodianAddress,
        address auditorAddress,
        address insuranceProvider,
        uint256 reserveRatioBps,
        bytes32 attestationHash
    ) external onlyRole(CUSTODY_ADMIN_ROLE) {
        if (custodyMappings[assetSymbol].custodianAddress == address(0)) {
            assetSymbols.push(assetSymbol);
        }

        custodyMappings[assetSymbol] = CustodyMapping({
            assetSymbol: assetSymbol,
            custodianName: custodianName,
            custodianAddress: custodianAddress,
            auditorAddress: auditorAddress,
            insuranceProvider: insuranceProvider,
            reserveRatioBps: reserveRatioBps,
            lastAttestationDate: block.timestamp,
            attestationHash: attestationHash,
            active: true
        });

        emit CustodyMapped(assetSymbol, custodianName, custodianAddress, reserveRatioBps);
    }

    function getCustodyMapping(string calldata assetSymbol) external view returns (CustodyMapping memory) {
        return custodyMappings[assetSymbol];
    }

    function _initializeDefaults() internal {
        _addDefault("USDC", "Circle Custody", address(0x1111), address(0x2222), 10000, keccak256("CIRCLE_RESERVE_ATT"));
        _addDefault("BUIDL", "BNY Mellon", address(0x3333), address(0x4444), 10000, keccak256("BNY_MELLON_ATT"));
        _addDefault("BENJI", "Franklin Templeton Transfer Agent", address(0x5555), address(0x6666), 10000, keccak256("FRANKLIN_ATT"));
        _addDefault("USDF", "BitGo Trust / Unykorn Custody", address(0x7777), address(0x8888), 10000, keccak256("UNYKORN_BITGO_ATT"));
    }

    function _addDefault(
        string memory symbol,
        string memory cName,
        address cAddr,
        address audAddr,
        uint256 bps,
        bytes32 attHash
    ) internal {
        custodyMappings[symbol] = CustodyMapping({
            assetSymbol: symbol,
            custodianName: cName,
            custodianAddress: cAddr,
            auditorAddress: audAddr,
            insuranceProvider: address(0),
            reserveRatioBps: bps,
            lastAttestationDate: block.timestamp,
            attestationHash: attHash,
            active: true
        });
        assetSymbols.push(symbol);
    }
}
