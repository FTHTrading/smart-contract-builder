// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title REITDistributor
/// @notice Pull-based per-unit distribution via an accumulator. Sponsor
///         deposits USDC (or other currency); every holder can claim their
///         accumulated dividend at any time. Balance changes are settled by
///         the DistributionToken's _update hook.
contract REITDistributor is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SPONSOR_ROLE = keccak256("SPONSOR_ROLE");
    bytes32 public constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    uint256 public constant PRECISION = 1e18;

    IERC20 public immutable currency;
    /// The unit token whose holders receive distributions.
    address public immutable unitToken;

    /// Cumulative currency-per-unit (scaled by PRECISION). Updated on each deposit.
    uint256 public accCurrencyPerUnit;
    /// Sum of all currency deposited to date.
    uint256 public totalDeposited;
    /// Sum of all currency claimed to date.
    uint256 public totalClaimed;
    /// Number of periods (deposits) processed.
    uint256 public periodCount;

    /// Per-holder "reward debt" — the accumulator level at the last time
    /// their balance changed. Claimable = balance * (accCurrencyPerUnit - debtCursor[h]) / PRECISION.
    mapping(address => uint256) public debtCursor;
    /// Per-holder unclaimed carry (accrued during transfers, not yet pulled).
    mapping(address => uint256) public pendingReward;

    event PeriodDeposited(uint256 indexed periodIndex, uint256 amount, uint256 totalSupply, uint256 accPerUnit);
    event Claimed(address indexed investor, uint256 amount);

    error ZeroDeposit();
    error NoUnclaimed();
    error NoUnits();
    error OnlyToken();

    constructor(address admin, address sponsor, address unitToken_, address currency_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SPONSOR_ROLE, sponsor);
        _grantRole(TOKEN_ROLE, unitToken_);
        unitToken = unitToken_;
        currency = IERC20(currency_);
    }

    /// @notice Sponsor deposits currency for the current period. Total supply
    ///         used for the per-unit calc is the live totalSupply() at deposit
    ///         time — investors who mint AFTER don't dilute prior period's math
    ///         because their debtCursor starts at the current (higher) accumulator.
    function deposit(uint256 amount) external onlyRole(SPONSOR_ROLE) {
        if (amount == 0) revert ZeroDeposit();
        uint256 supply = IERC20(unitToken).totalSupply();
        if (supply == 0) revert NoUnits();
        accCurrencyPerUnit += (amount * PRECISION) / supply;
        totalDeposited += amount;
        periodCount++;
        currency.safeTransferFrom(msg.sender, address(this), amount);
        emit PeriodDeposited(periodCount - 1, amount, supply, accCurrencyPerUnit);
    }

    /// @notice Called by the DistributionToken's _update hook. Settles debt
    ///         for both parties before the balance change so the accumulator
    ///         math stays correct.
    function onBalanceChanged(address from, address to, uint256) external onlyRole(TOKEN_ROLE) {
        if (from != address(0)) _accrue(from);
        if (to != address(0) && to != from) _accrue(to);
    }

    function _accrue(address holder) internal {
        uint256 bal = IERC20(unitToken).balanceOf(holder);
        uint256 owed = (bal * (accCurrencyPerUnit - debtCursor[holder])) / PRECISION;
        if (owed > 0) pendingReward[holder] += owed;
        debtCursor[holder] = accCurrencyPerUnit;
    }

    function claimable(address holder) public view returns (uint256) {
        uint256 bal = IERC20(unitToken).balanceOf(holder);
        uint256 owed = (bal * (accCurrencyPerUnit - debtCursor[holder])) / PRECISION;
        return pendingReward[holder] + owed;
    }

    function claim() external nonReentrant {
        _accrue(msg.sender);
        uint256 due = pendingReward[msg.sender];
        if (due == 0) revert NoUnclaimed();
        pendingReward[msg.sender] = 0;
        totalClaimed += due;
        currency.safeTransfer(msg.sender, due);
        emit Claimed(msg.sender, due);
    }
}
