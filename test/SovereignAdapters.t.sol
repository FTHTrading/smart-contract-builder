// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/adapters/XRPLHooksAdapter.sol";
import "../contracts/adapters/StellarAssetAdapter.sol";
import "../contracts/sovereign/ATP7332Registry.sol";
import "../contracts/sovereign/MomentRelicVault.sol";

contract SovereignAdaptersTest is Test {
    XRPLHooksAdapter public xrplAdapter;
    StellarAssetAdapter public stellarAdapter;
    ATP7332Registry public atpRegistry;
    MomentRelicVault public relicVault;

    address public admin = address(1);
    address public user = address(2);

    function setUp() public {
        vm.startPrank(admin);
        xrplAdapter = new XRPLHooksAdapter(admin);
        stellarAdapter = new StellarAssetAdapter(admin);
        atpRegistry = new ATP7332Registry(admin);
        relicVault = new MomentRelicVault("https://api.unykorn.ai/relics/", admin);
        vm.stopPrank();
    }

    function test_ATP7332Registry_RegisterRoot() public {
        vm.prank(admin);
        atpRegistry.registerSovereignRoot(".unykorn", keccak256("GENESIS"), admin, true);

        (string memory suffix, bytes32 gHash, address owner,, bool isGenesis, bool active) = atpRegistry.roots(".unykorn");
        assertEq(suffix, ".unykorn");
        assertEq(gHash, keccak256("GENESIS"));
        assertEq(owner, admin);
        assertTrue(isGenesis);
        assertTrue(active);
    }

    function test_MomentRelicVault_MintAndValuation() public {
        vm.startPrank(admin);
        relicVault.mintRelic(1, "Moment Relic #1", keccak256("RELIC1"), 1_000_000 * 1e18, user, 1);

        assertEq(relicVault.balanceOf(user, 1), 1);

        relicVault.setRelicValuation(1, 1_500_000 * 1e18);
        (, , , uint256 newValuation,) = relicVault.relics(1);
        assertEq(newValuation, 1_500_000 * 1e18);
        vm.stopPrank();
    }

    function test_XRPLBridge_Completion() public {
        bytes32 txHash = keccak256("XRPL_TX_1");

        vm.prank(admin);
        xrplAdapter.completeXRPLBridge(txHash, user, 500 * 1e18, "USDF", keccak256("ISSUER"));

        (bytes32 rHash, address recipient, uint256 amount,, , bool processed) = xrplAdapter.pendingRequests(txHash);
        assertEq(rHash, txHash);
        assertEq(recipient, user);
        assertEq(amount, 500 * 1e18);
        assertTrue(processed);
    }
}
