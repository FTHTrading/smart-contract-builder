// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/stablecoins/USDFStablecoin.sol";

contract MockPoRGuard is IProofOfReserveGuard {
    bool public mintAllowed = true;

    function setMintAllowed(bool allowed) external {
        mintAllowed = allowed;
    }

    function isMintAllowed(uint256) external view override returns (bool) {
        return mintAllowed;
    }
}

contract USDFStablecoinTest is Test {
    USDFStablecoin public usdf;
    MockPoRGuard public porGuard;

    address public admin = address(1);
    address public treasury = address(2);
    address public alice = address(3);
    address public bob = address(4);

    function setUp() public {
        porGuard = new MockPoRGuard();

        vm.startPrank(admin);
        usdf = new USDFStablecoin(
            "Unykorn Sovereign USD",
            "USDF",
            admin,
            treasury,
            address(porGuard)
        );
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(usdf.name(), "Unykorn Sovereign USD");
        assertEq(usdf.symbol(), "USDF");
        assertEq(usdf.treasury(), treasury);
        assertEq(usdf.proofOfReserveGuard(), address(porGuard));
    }

    function test_Mint_Success() public {
        vm.prank(admin);
        usdf.mint(alice, 1000 * 1e18);

        assertEq(usdf.balanceOf(alice), 1000 * 1e18);
    }

    function test_Mint_BlockedByPoR() public {
        porGuard.setMintAllowed(false);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(USDFStablecoin.ProofOfReserveMintBlocked.selector, 1000 * 1e18));
        usdf.mint(alice, 1000 * 1e18);
    }

    function test_SanctionsFreezeAndForceTransfer() public {
        vm.startPrank(admin);
        usdf.mint(alice, 1000 * 1e18);

        usdf.freezeAccount(alice);
        assertTrue(usdf.isFrozen(alice));

        // Alice transfer blocked
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(USDFStablecoin.AccountIsBlacklisted.selector, alice));
        usdf.transfer(bob, 500 * 1e18);

        // Compliance force transfer to treasury
        vm.prank(admin);
        usdf.complianceForceTransfer(alice, treasury, 1000 * 1e18);

        assertEq(usdf.balanceOf(alice), 0);
        assertEq(usdf.balanceOf(treasury), 1000 * 1e18);
    }

    function testFuzz_Mint(uint96 amount) public {
        vm.assume(amount > 0);

        vm.prank(admin);
        usdf.mint(alice, uint256(amount));

        assertEq(usdf.balanceOf(alice), uint256(amount));
    }
}
