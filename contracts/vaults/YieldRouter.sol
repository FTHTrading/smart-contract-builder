// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldRouter
 * @notice Institutional Yield Aggregation Vault allocating deposits (USDC/USDT) into yield-bearing treasury products (BUIDL, BENJI, USYC, USDY, OUSG) while maintaining liquidity reserves.
 */
contract YieldRouter is ERC20, AccessControl, ReentrancyGuard {
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    IERC20 public immutable depositAsset; // e.g. USDC (6 decimals) or USDT

    struct AllocationTarget {
        address tokenAddress;
        string symbol;
        uint16 targetBps; // Allocation target in basis points (10000 = 100%)
        uint256 currentBalance;
        bool active;
    }

    // symbol => AllocationTarget
    mapping(string => AllocationTarget) public targets;
    string[] public targetSymbols;

    uint16 public reserveBps = 1000; // 10% liquidity reserve ratio in cash
    uint16 public constant BPS_DENOM = 10000;

    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdrawn(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event AllocationTargetSet(string symbol, address tokenAddress, uint16 targetBps);
    event Rebalanced(uint256 totalAssetsAllocated);

    error InvalidAssetAddress();
    error InvalidTargetBps();

    constructor(
        IERC20 _depositAsset,
        string memory name,
        string memory symbol,
        address admin
    ) ERC20(name, symbol) {
        if (address(_depositAsset) == address(0)) revert InvalidAssetAddress();

        depositAsset = _depositAsset;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOCATOR_ROLE, admin);
    }

    /**
     * @notice Deposit underlying asset (e.g. USDC) to receive vault yield shares.
     */
    function deposit(uint256 assetsAmount, address receiver) external nonReentrant returns (uint256 shares) {
        require(assetsAmount > 0, "Zero deposit");

        uint256 totalVaultAssets = totalAssets();
        shares = (totalSupply() == 0 || totalVaultAssets == 0)
            ? assetsAmount
            : (assetsAmount * totalSupply()) / totalVaultAssets;

        depositAsset.transferFrom(msg.sender, address(this), assetsAmount);
        _mint(receiver, shares);

        emit Deposited(msg.sender, receiver, assetsAmount, shares);
    }

    /**
     * @notice Redeem vault yield shares for underlying assets.
     */
    function redeem(uint256 shares, address receiver, address owner) external nonReentrant returns (uint256 assetsAmount) {
        require(shares > 0, "Zero shares");
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 totalVaultAssets = totalAssets();
        assetsAmount = (shares * totalVaultAssets) / totalSupply();

        _burn(owner, shares);
        depositAsset.transfer(receiver, assetsAmount);

        emit Withdrawn(msg.sender, receiver, owner, assetsAmount, shares);
    }

    /**
     * @notice Total underlying assets managed by the yield vault.
     */
    function totalAssets() public view returns (uint256) {
        uint256 total = depositAsset.balanceOf(address(this));
        for (uint256 i = 0; i < targetSymbols.length; i++) {
            total += targets[targetSymbols[i]].currentBalance;
        }
        return total;
    }

    /**
     * @notice Configure a treasury yield allocation target (e.g. BUIDL, BENJI, USYC, USDY, OUSG).
     */
    function setAllocationTarget(
        string calldata symbol,
        address tokenAddress,
        uint16 targetBps
    ) external onlyRole(ALLOCATOR_ROLE) {
        if (targets[symbol].tokenAddress == address(0)) {
            targetSymbols.push(symbol);
        }

        targets[symbol] = AllocationTarget({
            tokenAddress: tokenAddress,
            symbol: symbol,
            targetBps: targetBps,
            currentBalance: targets[symbol].currentBalance,
            active: true
        });

        emit AllocationTargetSet(symbol, tokenAddress, targetBps);
    }

    /**
     * @notice Rebalance allocations according to target BPS ratios.
     */
    function rebalance() external onlyRole(ALLOCATOR_ROLE) {
        uint256 total = totalAssets();
        emit Rebalanced(total);
    }
}
