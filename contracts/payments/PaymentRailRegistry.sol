// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PaymentRailRegistry
 * @notice Global Fiat & Digital Settlement Rail Catalog mapping Fedwire, ACH, SEPA, SWIFT, RTP, FedNow, CHAPS, and TARGET2 to stablecoins and custody accounts.
 */
contract PaymentRailRegistry is AccessControl {
    bytes32 public constant RAIL_ADMIN_ROLE = keccak256("RAIL_ADMIN_ROLE");

    enum RailType {
        Fedwire,
        ACH,
        SEPA,
        SWIFT,
        RTP,
        FedNow,
        CHAPS,
        TARGET2
    }

    struct PaymentRail {
        string code;
        string name;
        RailType railType;
        string jurisdiction;
        string operatingHours;
        uint256 maxInstantLimitUSD;
        bool active;
    }

    mapping(bytes32 => PaymentRail) private rails;
    bytes32[] private railKeys;

    // assetSymbol => railCodes
    mapping(string => bytes32[]) private assetRails;

    event RailRegistered(string code, string name, RailType indexed railType, string jurisdiction);
    event AssetRailMapped(string indexed assetSymbol, string indexed railCode);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RAIL_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerRail(PaymentRail calldata rail) external onlyRole(RAIL_ADMIN_ROLE) {
        bytes32 key = _key(rail.code);
        rails[key] = rail;
        railKeys.push(key);

        emit RailRegistered(rail.code, rail.name, rail.railType, rail.jurisdiction);
    }

    function mapAssetToRail(string calldata assetSymbol, string calldata railCode) external onlyRole(RAIL_ADMIN_ROLE) {
        bytes32 key = _key(railCode);
        require(bytes(rails[key].code).length > 0, "Rail missing");

        assetRails[assetSymbol].push(key);
        emit AssetRailMapped(assetSymbol, railCode);
    }

    function getRail(string calldata code) external view returns (PaymentRail memory) {
        return rails[_key(code)];
    }

    function getAssetRails(string calldata assetSymbol) external view returns (bytes32[] memory) {
        return assetRails[assetSymbol];
    }

    function _key(string memory code) internal pure returns (bytes32) {
        return keccak256(bytes(code));
    }

    function _initializeDefaults() internal {
        _addDefault("FEDWIRE", "Federal Reserve Wire Network", RailType.Fedwire, "US", "24/7", 100_000_000 * 1e18);
        _addDefault("FEDNOW", "Federal Reserve FedNow Service", RailType.FedNow, "US", "24/7/365", 500_000 * 1e18);
        _addDefault("SEPA", "Single Euro Payments Area", RailType.SEPA, "EU", "24/7/365", 100_000 * 1e18);
        _addDefault("SWIFT", "SWIFT Global Banking Network", RailType.SWIFT, "GLOBAL", "24/5", 1_000_000_000 * 1e18);
    }

    function _addDefault(
        string memory code,
        string memory name,
        RailType rType,
        string memory jurisdiction,
        string memory hoursText,
        uint256 maxLimit
    ) internal {
        bytes32 key = _key(code);
        rails[key] = PaymentRail({
            code: code,
            name: name,
            railType: rType,
            jurisdiction: jurisdiction,
            operatingHours: hoursText,
            maxInstantLimitUSD: maxLimit,
            active: true
        });
        railKeys.push(key);
    }
}
