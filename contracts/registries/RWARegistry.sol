// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RWARegistry
 * @notice Institutional Real-World Asset Registry categorizing Treasuries, Private Credit, Real Estate, Commodities, Carbon, and Trade Finance.
 */
contract RWARegistry is AccessControl {
    bytes32 public constant RWA_ADMIN_ROLE = keccak256("RWA_ADMIN_ROLE");

    enum AssetClass {
        Treasury,
        PrivateCredit,
        RealEstate,
        Commodity,
        CarbonCredit,
        TradeFinance,
        Equity,
        Infrastructure
    }

    struct RWAAsset {
        bytes32 assetId;
        string name;
        string symbol;
        AssetClass assetClass;
        string legalStructure; // e.g. "Delaware LLC SPV", "Statutory Trust"
        string documentHash;   // LPS-1 SHA-256 document anchor
        uint256 totalValuationUSD;
        address contractAddress;
        bool active;
    }

    mapping(bytes32 => RWAAsset) public rwaAssets;
    bytes32[] public rwaAssetKeys;

    event RWAAssetRegistered(bytes32 indexed assetId, string name, AssetClass indexed assetClass, uint256 valuationUSD);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RWA_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerRWAAsset(
        string calldata name,
        string calldata symbol,
        AssetClass assetClass,
        string calldata legalStructure,
        string calldata documentHash,
        uint256 valuationUSD,
        address contractAddress
    ) external onlyRole(RWA_ADMIN_ROLE) returns (bytes32 assetId) {
        assetId = keccak256(abi.encodePacked(name, symbol, block.timestamp));

        rwaAssets[assetId] = RWAAsset({
            assetId: assetId,
            name: name,
            symbol: symbol,
            assetClass: assetClass,
            legalStructure: legalStructure,
            documentHash: documentHash,
            totalValuationUSD: valuationUSD,
            contractAddress: contractAddress,
            active: true
        });

        rwaAssetKeys.push(assetId);
        emit RWAAssetRegistered(assetId, name, assetClass, valuationUSD);
    }

    function getRWAAsset(bytes32 assetId) external view returns (RWAAsset memory) {
        return rwaAssets[assetId];
    }

    function _initializeDefaults() internal {
        bytes32 helenId = keccak256("M_HELEN_HOTEL_SPV");
        rwaAssets[helenId] = RWAAsset({
            assetId: helenId,
            name: "M Helen Hotel LLC SPV",
            symbol: "HELEN",
            assetClass: AssetClass.RealEstate,
            legalStructure: "Georgia LLC Statutory Waiver SPV",
            documentHash: "0x7777777777777777777777777777777777777777777777777777777777777777",
            totalValuationUSD: 25_000_000 * 1e18,
            contractAddress: address(0x8888),
            active: true
        });
        rwaAssetKeys.push(helenId);
    }
}
