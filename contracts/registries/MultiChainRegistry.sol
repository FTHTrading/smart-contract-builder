// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title MultiChainRegistry
 * @notice Universal Canonical Settlement & Token-Discovery Registry spanning EVM, XRPL, Stellar, Solana, Apostle Chain, Canton Network, DTCC DLT, and Swift DLT Gateways.
 * @dev Manages 28 institutional, regulated, treasury, and DeFi stablecoin asset definitions across 18 settlement networks.
 */
contract MultiChainRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    struct NetworkInfo {
        string name;
        uint256 chainId; // 0 for non-EVM networks (Canton, DTCC, Swift, XRPL L1, Stellar, Solana)
        uint64 ccipChainSelector;
        address ccipRouter;
        string architecture; // "EVM", "Canton", "DTCC", "Swift", "XRPL", "Stellar", "Solana", "Apostle"
        bool active;
    }

    struct AssetInfo {
        string symbol;
        string name;
        string issuer;
        string network;
        uint256 chainId;
        address tokenAddress;
        uint8 decimals;
        bool regulated;
        bool institutional;
        bool fiatBacked;
        bool active;
    }

    // chainId => NetworkInfo
    mapping(uint256 => NetworkInfo) public networks;
    // chainId => (symbol => AssetInfo)
    mapping(uint256 => mapping(string => AssetInfo)) public assets;

    uint256[] public registeredChainIds;

    event NetworkRegistered(uint256 indexed chainId, string name, string architecture, uint64 ccipChainSelector);
    event AssetRegistered(uint256 indexed chainId, string indexed symbol, string issuer, address tokenAddress);

    error NetworkNotFound(uint256 chainId);
    error AssetNotFound(uint256 chainId, string symbol);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);

        _initializeNetworks();
        _initializeAssets();
    }

    function registerNetwork(
        uint256 chainId,
        string calldata name,
        uint64 ccipChainSelector,
        address ccipRouter,
        string calldata architecture
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        NetworkInfo storage n = networks[chainId];
        n.name = name;
        n.chainId = chainId;
        n.ccipChainSelector = ccipChainSelector;
        n.ccipRouter = ccipRouter;
        n.architecture = architecture;
        n.active = true;

        registeredChainIds.push(chainId);
        emit NetworkRegistered(chainId, name, architecture, ccipChainSelector);
    }

    function registerAsset(
        uint256 chainId,
        string calldata symbol,
        string calldata name,
        string calldata issuer,
        string calldata networkName,
        address tokenAddress,
        uint8 decimals,
        bool regulated,
        bool institutional,
        bool fiatBacked
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        AssetInfo storage a = assets[chainId][symbol];
        a.symbol = symbol;
        a.name = name;
        a.issuer = issuer;
        a.network = networkName;
        a.chainId = chainId;
        a.tokenAddress = tokenAddress;
        a.decimals = decimals;
        a.regulated = regulated;
        a.institutional = institutional;
        a.fiatBacked = fiatBacked;
        a.active = true;

        emit AssetRegistered(chainId, symbol, issuer, tokenAddress);
    }

    function getNetwork(uint256 chainId) external view returns (NetworkInfo memory) {
        if (!networks[chainId].active) revert NetworkNotFound(chainId);
        return networks[chainId];
    }

    function getAsset(uint256 chainId, string calldata symbol) external view returns (AssetInfo memory) {
        if (!assets[chainId][symbol].active) revert AssetNotFound(chainId, symbol);
        return assets[chainId][symbol];
    }

    function _setNetwork(
        uint256 chainId,
        string memory name,
        uint64 selector,
        address router,
        string memory arch
    ) internal {
        NetworkInfo storage n = networks[chainId];
        n.name = name;
        n.chainId = chainId;
        n.ccipChainSelector = selector;
        n.ccipRouter = router;
        n.architecture = arch;
        n.active = true;
    }

    function _setAsset(
        uint256 chainId,
        string memory symbol,
        string memory name,
        string memory issuer,
        address token,
        uint8 decimals,
        bool reg,
        bool inst,
        bool fiat
    ) internal {
        AssetInfo storage a = assets[chainId][symbol];
        a.symbol = symbol;
        a.name = name;
        a.issuer = issuer;
        a.network = "Ethereum";
        a.chainId = chainId;
        a.tokenAddress = token;
        a.decimals = decimals;
        a.regulated = reg;
        a.institutional = inst;
        a.fiatBacked = fiat;
        a.active = true;
    }

    function _initializeNetworks() internal {
        _setNetwork(1, "Ethereum Mainnet", 5009297550715157269, 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D, "EVM");
        _setNetwork(137, "Polygon Mainnet", 4051577828743386545, 0x3c3D92629A02a8D616A76750286818806922d635, "EVM");
        _setNetwork(8453, "Base Mainnet", 15971525489660198786, 0x88108c451d4666b4610c8E19b2a4b022b8018E69, "EVM");
        _setNetwork(42161, "Arbitrum One", 4949039107694359620, address(0), "EVM");
        _setNetwork(10, "OP Mainnet", 3734403246176062670, address(0), "EVM");
        _setNetwork(43114, "Avalanche C-Chain", 6433500567565415381, address(0), "EVM");
        _setNetwork(56, "BNB Smart Chain", 1134466358939413612, address(0), "EVM");
        _setNetwork(7332, "Apostle Sovereign Chain", 733273327332, address(0), "Apostle");
        _setNetwork(1440002, "XRPL EVM Sidechain", 0, address(0), "XRPL");
        _setNetwork(0, "Canton Network Consortium", 0, address(0), "Canton");
        _setNetwork(9001, "DTCC DLT Infrastructure Mesh", 0, address(0), "DTCC");
        _setNetwork(9002, "Swift DLT Settlement Gateway", 0, address(0), "Swift");
    }

    function _initializeAssets() internal {
        _initTier1();
        _initTier2And3();
        _initTier4And5();
        _initWave2Institutional();
    }

    function _initTier1() internal {
        _setAsset(1, "USDC", "USD Coin", "Circle", address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), 6, true, true, true);
        _setAsset(1, "USDT", "Tether USD", "Tether", address(0xdAC17F958D2ee523a2206206994597C13D831ec7), 6, true, true, true);
        _setAsset(1, "USDF", "Unykorn Sovereign USD", "Unykorn", address(0), 18, true, true, true);
        _setAsset(1, "PYUSD", "PayPal USD", "PayPal/Paxos", address(0x6C3eA9036406852006290770bedaCaBA0E23a0E8), 6, true, true, true);
        _setAsset(1, "RLUSD", "Ripple USD", "Ripple", address(0), 6, true, true, true);
        _setAsset(1, "USDS", "Sky Dollar", "Sky Protocol", address(0), 18, false, false, false);
        _setAsset(1, "DAI", "Dai Stablecoin", "MakerDAO", address(0x6B175474E89094C44Da98b954EedeAC495271d0F), 18, false, false, false);
        _setAsset(1, "EURC", "Euro Coin", "Circle", address(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c), 6, true, true, true);
    }

    function _initTier2And3() internal {
        _setAsset(1, "USDP", "Pax Dollar", "Paxos", address(0x8E870D67F660D95d5be530380D0eC0bd388289E1), 18, true, true, true);
        _setAsset(1, "USDG", "Global Dollar", "Paxos Network", address(0), 6, true, true, true);

        _setAsset(1, "BUIDL", "BlackRock USD Institutional Digital Liquidity Fund", "BlackRock", address(0), 6, true, true, true);
        _setAsset(1, "BENJI", "Franklin OnChain U.S. Government Money Fund", "Franklin Templeton", address(0), 6, true, true, true);
        _setAsset(1, "USYC", "Circle Yield Coin", "Circle/Hashnote", address(0), 6, true, true, true);
        _setAsset(1, "USDY", "Ondo US Dollar Yield Token", "Ondo Finance", address(0), 18, true, true, true);
    }

    function _initTier4And5() internal {
        _setAsset(1, "USDe", "Ethena USDe", "Ethena", address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3), 18, false, false, false);
        _setAsset(1, "GHO", "GHO Token", "Aave", address(0x40d16Fc13A55145A45a301285A06a26669dBc681), 18, false, false, false);
        _setAsset(1, "crvUSD", "Curve DAO USD", "Curve", address(0xf939e0a03Fb07f2188A11e27799717857599b31e), 18, false, false, false);
        _setAsset(1, "FRAX", "Frax Stablecoin", "Frax Finance", address(0x853d955aCEf822Db058eb8505911ED77F175b99e), 18, false, false, false);

        _setAsset(1, "FDUSD", "First Digital USD", "First Digital", address(0xc5f0f7b66764F6ec8C8Dff7BA683102295E16409), 18, true, true, true);
        _setAsset(1, "TUSD", "TrueUSD", "Archblock", address(0x0000000000085d4780B73119b644AE5ecd22b376), 18, true, true, true);
        _setAsset(1, "GUSD", "Gemini Dollar", "Gemini", address(0x056Fd409e1d7A124BD7017459DFEa235F21d6512), 2, true, true, true);
        _setAsset(1, "USD1", "World Liberty Financial USD", "World Liberty Financial", address(0), 18, true, true, true);
    }

    function _initWave2Institutional() internal {
        // Ondo Short-Term US Treasury
        _setAsset(1, "OUSG", "Ondo Short-Term US Government Bond Fund", "Ondo Finance", address(0x1b19c19393E2d034D8fF31fF34C81252dfbdfB35), 18, true, true, true);
        // BlackRock Treasury Fund Variant
        _setAsset(1, "BTF", "BlackRock Treasury Fund Token", "BlackRock", address(0), 6, true, true, true);
        // JPMorgan Treasury Token
        _setAsset(1, "JTRSY", "JPMorgan Institutional Treasury Token", "JPMorgan", address(0), 6, true, true, true);
        // Savings DAI
        _setAsset(1, "sDAI", "Savings Dai", "MakerDAO / Sky", address(0x83F20F44975D03b1b09e64809B757c47f942BEeA), 18, false, true, false);
        // Resolv USD
        _setAsset(1, "USR", "Resolv USD", "Resolv", address(0), 18, false, false, false);
        // BlackRock-Backed Ethena Reserve Token
        _setAsset(1, "USDTb", "BlackRock-Backed Ethena Reserve Token", "Ethena / BlackRock", address(0), 18, true, true, true);
    }
}
