// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/registries/RWARegistry.sol";
import "../contracts/settlement/StablecoinSettlementHub.sol";

contract RWAAndSettlementHubTest is Test {
    RWARegistry public rwaRegistry;
    StablecoinSettlementHub public settlementHub;

    address public admin = address(1);
    address public alice = address(2);

    function setUp() public {
        vm.startPrank(admin);
        rwaRegistry = new RWARegistry(admin);
        settlementHub = new StablecoinSettlementHub(admin);
        vm.stopPrank();
    }

    function test_DefaultRWAAsset_Helen() public view {
        bytes32 helenId = keccak256("M_HELEN_HOTEL_SPV");
        RWARegistry.RWAAsset memory asset = rwaRegistry.getRWAAsset(helenId);

        assertEq(asset.name, "M Helen Hotel LLC SPV");
        assertEq(asset.symbol, "HELEN");
        assertEq(uint256(asset.assetClass), uint256(RWARegistry.AssetClass.RealEstate));
        assertEq(asset.totalValuationUSD, 25_000_000 * 1e18);
    }

    function test_RegisterRWAAsset() public {
        vm.prank(admin);
        bytes32 assetId = rwaRegistry.registerRWAAsset(
            "EV Charger Inventory SPV",
            "EVCHG",
            RWARegistry.AssetClass.PrivateCredit,
            "Delaware LLC SPV",
            "0x1111222233334444555566667777888899990000",
            2_000_000 * 1e18,
            address(0x777)
        );

        RWARegistry.RWAAsset memory asset = rwaRegistry.getRWAAsset(assetId);
        assertEq(asset.symbol, "EVCHG");
        assertEq(uint256(asset.assetClass), uint256(RWARegistry.AssetClass.PrivateCredit));
    }

    function test_SettlementHub_RegistrationAndLiquidity() public {
        vm.startPrank(admin);
        settlementHub.registerTokenPool("USDC", address(0x111));
        settlementHub.registerTokenPool("USDF", address(0x222));

        settlementHub.addLiquidity("USDF", 1_000_000 * 1e18);
        vm.stopPrank();

        (address token, string memory symbol, uint256 reserve, bool active) = settlementHub.pools("USDF");
        assertEq(symbol, "USDF");
        assertEq(reserve, 1_000_000 * 1e18);
        assertTrue(active);
    }
}
