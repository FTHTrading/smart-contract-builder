// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title MultiChainRegistry
 * @notice Canonical registry for multi-chain routing, CCIP chain selectors, stablecoin contracts, and network constants.
 */
contract MultiChainRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    struct ChainInfo {
        uint64 ccipChainSelector;
        uint256 chainId;
        string name;
        address ccipRouter;
        bool isEVM;
        bool active;
    }

    struct AssetInfo {
        string symbol;
        string name;
        uint8 decimals;
        address contractAddress;
        bool isStablecoin;
        bool active;
    }

    // chainId => ChainInfo
    mapping(uint256 => ChainInfo) public chains;
    // chainId => (symbol => AssetInfo)
    mapping(uint256 => mapping(string => AssetInfo)) public assets;

    event ChainRegistered(uint256 indexed chainId, uint64 ccipChainSelector, string name, address ccipRouter);
    event AssetRegistered(uint256 indexed chainId, string indexed symbol, address contractAddress, bool isStablecoin);

    error ChainNotFound(uint256 chainId);
    error AssetNotFound(uint256 chainId, string symbol);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerChain(
        uint256 chainId,
        uint64 ccipChainSelector,
        string calldata name,
        address ccipRouter,
        bool isEVM
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        chains[chainId] = ChainInfo({
            ccipChainSelector: ccipChainSelector,
            chainId: chainId,
            name: name,
            ccipRouter: ccipRouter,
            isEVM: isEVM,
            active: true
        });
        emit ChainRegistered(chainId, ccipChainSelector, name, ccipRouter);
    }

    function registerAsset(
        uint256 chainId,
        string calldata symbol,
        string calldata name,
        uint8 decimals,
        address contractAddress,
        bool isStablecoin
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        assets[chainId][symbol] = AssetInfo({
            symbol: symbol,
            name: name,
            decimals: decimals,
            contractAddress: contractAddress,
            isStablecoin: isStablecoin,
            active: true
        });
        emit AssetRegistered(chainId, symbol, contractAddress, isStablecoin);
    }

    function getChain(uint256 chainId) external view returns (ChainInfo memory) {
        if (!chains[chainId].active) revert ChainNotFound(chainId);
        return chains[chainId];
    }

    function getAsset(uint256 chainId, string calldata symbol) external view returns (AssetInfo memory) {
        if (!assets[chainId][symbol].active) revert AssetNotFound(chainId, symbol);
        return assets[chainId][symbol];
    }

    function _initializeDefaults() internal {
        // Ethereum Mainnet (1)
        chains[1] = ChainInfo(5009297550715157269, 1, "Ethereum Mainnet", 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D, true, true);
        assets[1]["USDC"] = AssetInfo("USDC", "USD Coin", 6, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, true, true);
        assets[1]["USDT"] = AssetInfo("USDT", "Tether USD", 6, 0xdAC17F958D2ee523a2206206994597C13D831ec7, true, true);
        assets[1]["PYUSD"] = AssetInfo("PYUSD", "PayPal USD", 6, 0x6C3eA9036406852006290770bedaCaBA0E23a0E8, true, true);

        // Polygon Mainnet (137)
        chains[137] = ChainInfo(4051577828743386545, 137, "Polygon Mainnet", 0x3c3D92629A02a8D616A76750286818806922d635, true, true);
        assets[137]["USDC"] = AssetInfo("USDC", "USD Coin", 6, 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, true, true);

        // Base Mainnet (8453)
        chains[8453] = ChainInfo(15971525489660198786, 8453, "Base Mainnet", 0x88108c451d4666b4610c8E19b2a4b022b8018E69, true, true);
        assets[8453]["USDC"] = AssetInfo("USDC", "USD Coin", 6, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, true, true);

        // Apostle Chain (7332)
        chains[7332] = ChainInfo(733273327332, 7332, "Apostle Sovereign Chain", address(0), true, true);
    }
}
