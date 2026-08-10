// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ValuationOracle
 * @notice System-wide Valuation & Yield Oracle tracking Net Asset Values (NAV), spot prices, yield percentages, reserve ratios, and attestation timestamps.
 */
contract ValuationOracle is AccessControl {
    bytes32 public constant VALUATION_ADMIN_ROLE = keccak256("VALUATION_ADMIN_ROLE");

    struct AssetValuation {
        string symbol;
        uint256 priceUSD;       // scaled 1e18
        uint256 yieldBps;       // Annual Yield in Basis Points (e.g. 520 = 5.20%)
        uint256 reserveRatioBps;// e.g. 10000 = 100%
        uint256 updatedAt;
        bytes32 proofHash;
        bool active;
    }

    // symbol => AssetValuation
    mapping(string => AssetValuation) public valuations;
    string[] public assetSymbols;

    event ValuationUpdated(string indexed symbol, uint256 priceUSD, uint256 yieldBps, uint256 reserveRatioBps);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VALUATION_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function setValuation(
        string calldata symbol,
        uint256 priceUSD,
        uint256 yieldBps,
        uint256 reserveRatioBps,
        bytes32 proofHash
    ) external onlyRole(VALUATION_ADMIN_ROLE) {
        if (valuations[symbol].priceUSD == 0) {
            assetSymbols.push(symbol);
        }

        valuations[symbol] = AssetValuation({
            symbol: symbol,
            priceUSD: priceUSD,
            yieldBps: yieldBps,
            reserveRatioBps: reserveRatioBps,
            updatedAt: block.timestamp,
            proofHash: proofHash,
            active: true
        });

        emit ValuationUpdated(symbol, priceUSD, yieldBps, reserveRatioBps);
    }

    function getValuation(string calldata symbol) external view returns (AssetValuation memory) {
        return valuations[symbol];
    }

    function _initializeDefaults() internal {
        _addDefault("USDC", 1.00 * 1e18, 0, 10000, keccak256("USDC_VAL"));
        _addDefault("USDF", 1.00 * 1e18, 500, 10000, keccak256("USDF_VAL")); // 5.00% yield
        _addDefault("BUIDL", 1.00 * 1e18, 525, 10000, keccak256("BUIDL_VAL")); // 5.25% yield
        _addDefault("BENJI", 1.00 * 1e18, 515, 10000, keccak256("BENJI_VAL")); // 5.15% yield
        _addDefault("USDY", 1.05 * 1e18, 530, 10000, keccak256("USDY_VAL")); // 5.30% yield
    }

    function _addDefault(string memory symbol, uint256 price, uint256 yieldBps, uint256 reserveBps, bytes32 proof) internal {
        valuations[symbol] = AssetValuation({
            symbol: symbol,
            priceUSD: price,
            yieldBps: yieldBps,
            reserveRatioBps: reserveBps,
            updatedAt: block.timestamp,
            proofHash: proof,
            active: true
        });
        assetSymbols.push(symbol);
    }
}
