// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/vaults/YieldRouter.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 1e6);
    }
}

contract YieldRouterTest is Test {
    YieldRouter public router;
    MockUSDC public usdc;

    address public admin = address(1);
    address public alice = address(2);

    function setUp() public {
        usdc = new MockUSDC();

        vm.startPrank(admin);
        router = new YieldRouter(IERC20(address(usdc)), "Unykorn Treasury Yield Vault", "yUSDC", admin);
        vm.stopPrank();

        usdc.transfer(alice, 100_000 * 1e6);
    }

    function test_DepositAndRedeem() public {
        vm.startPrank(alice);
        usdc.approve(address(router), 10_000 * 1e6);

        uint256 shares = router.deposit(10_000 * 1e6, alice);
        assertEq(shares, 10_000 * 1e6);
        assertEq(router.balanceOf(alice), 10_000 * 1e6);

        router.redeem(10_000 * 1e6, alice, alice);
        assertEq(usdc.balanceOf(alice), 100_000 * 1e6);
        vm.stopPrank();
    }

    function test_SetAllocationTarget() public {
        vm.prank(admin);
        router.setAllocationTarget("BUIDL", address(0x888), 4000);

        (address token, string memory symbol, uint16 targetBps, uint256 currentBal, bool active) = router.targets("BUIDL");
        assertEq(symbol, "BUIDL");
        assertEq(token, address(0x888));
        assertEq(targetBps, 4000);
        assertTrue(active);
    }
}
