// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ChainConstants
/// @notice Canonical mainnet addresses for common integrations, keyed by
///         chain ID. Deployment scripts should ALWAYS resolve infrastructure
///         addresses through this registry — hardcoding addresses in
///         individual deploy scripts is how testnet artifacts leak into
///         production configs.
///
///         This library is view-only and stateless — safe to call from
///         constructors and view functions. Every address is documented with
///         its source; verify before relying on any of them (addresses
///         change; deprecations happen).
library ChainConstants {
    // ---- Chain IDs ----
    uint256 internal constant ETH_MAINNET = 1;
    uint256 internal constant ETH_SEPOLIA = 11155111;
    uint256 internal constant POLYGON_MAINNET = 137;
    uint256 internal constant BASE_MAINNET = 8453;
    uint256 internal constant ARBITRUM_MAINNET = 42161;
    uint256 internal constant OPTIMISM_MAINNET = 10;
    uint256 internal constant AVALANCHE_MAINNET = 43114;
    uint256 internal constant BNB_MAINNET = 56;
    uint256 internal constant ANVIL_LOCAL = 31337;

    // ---- USDC (Circle) — verified from Circle's official docs ----
    function usdc(uint256 chainId) internal pure returns (address) {
        if (chainId == ETH_MAINNET) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (chainId == POLYGON_MAINNET) return 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
        if (chainId == BASE_MAINNET) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        if (chainId == ARBITRUM_MAINNET) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        if (chainId == OPTIMISM_MAINNET) return 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        if (chainId == AVALANCHE_MAINNET) return 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
        return address(0);
    }

    // ---- USDT (Tether) — verified from Tether's official docs ----
    function usdt(uint256 chainId) internal pure returns (address) {
        if (chainId == ETH_MAINNET) return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        if (chainId == POLYGON_MAINNET) return 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        if (chainId == ARBITRUM_MAINNET) return 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        if (chainId == OPTIMISM_MAINNET) return 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
        if (chainId == AVALANCHE_MAINNET) return 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
        return address(0);
    }

    // ---- Chainlink CCIP Router — from docs.chain.link/ccip/directory ----
    function ccipRouter(uint256 chainId) internal pure returns (address) {
        if (chainId == ETH_MAINNET) return 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
        if (chainId == POLYGON_MAINNET) return 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe;
        if (chainId == BASE_MAINNET) return 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
        if (chainId == ARBITRUM_MAINNET) return 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
        if (chainId == OPTIMISM_MAINNET) return 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f;
        if (chainId == AVALANCHE_MAINNET) return 0xF4c7E640EdA248ef95972845a62bdC74237805dB;
        if (chainId == BNB_MAINNET) return 0x34B03Cb9086d7D758AC55af71584F81A598759FE;
        return address(0);
    }

    // ---- CCIP Chain Selectors — DIFFERENT from chain IDs. From docs.chain.link/ccip/directory ----
    function ccipChainSelector(uint256 chainId) internal pure returns (uint64) {
        if (chainId == ETH_MAINNET) return 5009297550715157269;
        if (chainId == POLYGON_MAINNET) return 4051577828743386545;
        if (chainId == BASE_MAINNET) return 15971525489660198786;
        if (chainId == ARBITRUM_MAINNET) return 4949039107694359620;
        if (chainId == OPTIMISM_MAINNET) return 3734403246176062136;
        if (chainId == AVALANCHE_MAINNET) return 6433500567565415381;
        if (chainId == BNB_MAINNET) return 11344663589394136015;
        return 0;
    }

    // ---- Chainlink LINK Token (for CCIP fee payment in LINK) ----
    function link(uint256 chainId) internal pure returns (address) {
        if (chainId == ETH_MAINNET) return 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        if (chainId == POLYGON_MAINNET) return 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;
        if (chainId == BASE_MAINNET) return 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196;
        if (chainId == ARBITRUM_MAINNET) return 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
        if (chainId == OPTIMISM_MAINNET) return 0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6;
        if (chainId == AVALANCHE_MAINNET) return 0x5947BB275c521040051D82396192181b413227A3;
        if (chainId == BNB_MAINNET) return 0x404460C6A5EdE2D891e8297795264fDe62ADBB75;
        return address(0);
    }

    // ---- Chainlink price feeds (illustrative — verify before use) ----
    // Full directory: https://data.chain.link/feeds
    // ETH/USD feeds shown; add others per chain as needed.
    function ethUsdFeed(uint256 chainId) internal pure returns (address) {
        if (chainId == ETH_MAINNET) return 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        if (chainId == POLYGON_MAINNET) return 0xF9680D99D6C9589e2a93a78A04A279e509205945;
        if (chainId == BASE_MAINNET) return 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
        if (chainId == ARBITRUM_MAINNET) return 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        return address(0);
    }
}
