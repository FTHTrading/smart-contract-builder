// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/registries/MultiChainRegistry.sol";

contract MultiChainRegistryTest is Test {
    MultiChainRegistry public registry;
    address public admin = address(1);

    function setUp() public {
        vm.prank(admin);
        registry = new MultiChainRegistry(admin);
    }

    function test_GetNetwork_Ethereum() public view {
        MultiChainRegistry.NetworkInfo memory net = registry.getNetwork(1);
        assertEq(net.name, "Ethereum Mainnet");
        assertEq(keccak256(bytes(net.architecture)), keccak256(bytes("EVM")));
    }

    function test_GetNetwork_Canton() public view {
        MultiChainRegistry.NetworkInfo memory net = registry.getNetwork(0);
        assertEq(net.name, "Canton Network Consortium");
        assertEq(keccak256(bytes(net.architecture)), keccak256(bytes("Canton")));
    }

    function test_GetAsset_Tier1_USDC() public view {
        MultiChainRegistry.AssetInfo memory asset = registry.getAsset(1, "USDC");
        assertEq(asset.name, "USD Coin");
        assertEq(asset.issuer, "Circle");
        assertTrue(asset.regulated);
        assertTrue(asset.institutional);
        assertTrue(asset.fiatBacked);
    }

    function test_GetAsset_Tier2_USDG() public view {
        MultiChainRegistry.AssetInfo memory asset = registry.getAsset(1, "USDG");
        assertEq(asset.name, "Global Dollar");
        assertEq(asset.issuer, "Paxos Network");
        assertTrue(asset.regulated);
    }

    function test_GetAsset_Tier3_BUIDL() public view {
        MultiChainRegistry.AssetInfo memory asset = registry.getAsset(1, "BUIDL");
        assertEq(asset.name, "BlackRock USD Institutional Digital Liquidity Fund");
        assertEq(asset.issuer, "BlackRock");
        assertTrue(asset.institutional);
    }

    function test_RegisterNewAsset() public {
        vm.prank(admin);
        registry.registerAsset(
            1,
            "TEST",
            "Test Asset",
            "Unykorn Test",
            "Ethereum",
            address(0x123),
            18,
            true,
            true,
            true
        );

        MultiChainRegistry.AssetInfo memory asset = registry.getAsset(1, "TEST");
        assertEq(asset.issuer, "Unykorn Test");
        assertEq(asset.tokenAddress, address(0x123));
    }
}
