// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CashManagementVault
/// @notice ERC-4626-shape vault for on-chain cash management. Reference
///         shapes: Maple Cash Management (holds tokenized T-bills), Anchorage
///         cash sweep, Ondo Cash. Deposits USDC (or any base currency);
///         allocator strategy rebalances into yield-bearing RWA shares like
///         BlackRock BUIDL, Circle USYC, or Franklin BENJI while maintaining
///         a configurable reserve ratio for instant redemptions.
///
///         Simplified from full ERC-4626 (skips withdraw slippage checks and
///         the maxDeposit/maxRedeem bookkeeping) but implements the same
///         share↔asset accounting so it composes cleanly with ERC-4626-aware
///         indexers.
///
///         Rebalancing is a manual admin operation via `deployToYieldAsset` /
///         `withdrawFromYieldAsset` — production deployments would layer a
///         Chainlink Automation keeper that triggers rebalances on threshold
///         crossings.
contract CashManagementVault is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    uint256 public constant SCALE = 1e18;
    /// Basis points denominator.
    uint256 public constant BPS_DENOM = 10_000;

    IERC20 public immutable currency;
    /// The yield-bearing asset the vault deploys reserves into (e.g. BUIDL,
    /// USYC, BENJI). Assumed 1:1 with currency at all times — for treasury-
    /// backed shares this is a safe assumption (their NAV per share is stable);
    /// for non-1:1 assets, layer an oracle-based revaluation on top.
    IERC20 public immutable yieldAsset;

    /// Minimum reserve ratio of `currency` in the vault, in bps of total assets.
    /// e.g. 1_000 = 10% held in liquid currency, 90% deployed into yieldAsset.
    uint256 public minReserveBps;

    event Deposited(address indexed depositor, uint256 currencyAmount, uint256 sharesMinted);
    event Withdrawn(address indexed withdrawer, uint256 shares, uint256 currencyOut);
    event DeployedToYield(uint256 currencyOut, uint256 yieldAssetIn);
    event WithdrawnFromYield(uint256 yieldAssetOut, uint256 currencyIn);
    event MinReserveUpdated(uint256 bps);

    error BelowReserveMinimum(uint256 currentReserveBps, uint256 minReserveBps);
    error InsufficientCurrencyReserve(uint256 requested, uint256 available);
    error ZeroAmount();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address allocator,
        address currency_,
        address yieldAsset_,
        uint256 minReserveBps_
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOCATOR_ROLE, allocator);
        currency = IERC20(currency_);
        yieldAsset = IERC20(yieldAsset_);
        require(minReserveBps_ <= BPS_DENOM, "reserve > 100%");
        minReserveBps = minReserveBps_;
    }

    function setMinReserveBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bps <= BPS_DENOM, "reserve > 100%");
        minReserveBps = bps;
        emit MinReserveUpdated(bps);
    }

    // ---- ERC-4626-ish accounting ----

    function totalAssets() public view returns (uint256) {
        return currency.balanceOf(address(this)) + yieldAsset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return (assets * supply) / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return (shares * totalAssets()) / supply;
    }

    // ---- Deposit / withdraw ----

    function deposit(uint256 currencyAmount, address receiver) external nonReentrant returns (uint256 sharesMinted) {
        if (currencyAmount == 0) revert ZeroAmount();
        sharesMinted = convertToShares(currencyAmount);
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        _mint(receiver, sharesMinted);
        emit Deposited(receiver, currencyAmount, sharesMinted);
    }

    /// @notice Redeem shares for currency. Uses only the on-hand currency
    ///         reserve; if reserve is insufficient, caller must wait for the
    ///         allocator to withdraw from yield. This is the operational
    ///         tradeoff of any tokenized-fund cash management: yield vs
    ///         instant liquidity.
    function withdraw(uint256 shares, address receiver) external nonReentrant returns (uint256 currencyOut) {
        if (shares == 0) revert ZeroAmount();
        currencyOut = convertToAssets(shares);
        uint256 reserve = currency.balanceOf(address(this));
        if (currencyOut > reserve) {
            revert InsufficientCurrencyReserve(currencyOut, reserve);
        }
        _burn(msg.sender, shares);
        currency.safeTransfer(receiver, currencyOut);
        emit Withdrawn(msg.sender, shares, currencyOut);
    }

    // ---- Allocator (rebalancing) ----

    /// @notice Deploy currency into the yield-bearing asset. Caller must
    ///         have pre-approved this contract to pull yieldAsset (they've
    ///         run the yield asset's subscription flow already).
    ///
    ///         Simplifying assumption: 1 currency in → 1 yieldAsset out.
    ///         For non-1:1 pricing, replace this with an
    ///         oracle-priced conversion via a NAV feed.
    function deployToYieldAsset(uint256 currencyAmount) external nonReentrant onlyRole(ALLOCATOR_ROLE) {
        if (currencyAmount == 0) revert ZeroAmount();
        currency.safeTransfer(msg.sender, currencyAmount);
        yieldAsset.safeTransferFrom(msg.sender, address(this), currencyAmount);
        _checkReserveMinimum();
        emit DeployedToYield(currencyAmount, currencyAmount);
    }

    /// @notice Pull currency back from the yield asset (for redemption load).
    function withdrawFromYieldAsset(uint256 yieldAmount) external nonReentrant onlyRole(ALLOCATOR_ROLE) {
        if (yieldAmount == 0) revert ZeroAmount();
        yieldAsset.safeTransfer(msg.sender, yieldAmount);
        currency.safeTransferFrom(msg.sender, address(this), yieldAmount);
        emit WithdrawnFromYield(yieldAmount, yieldAmount);
    }

    function _checkReserveMinimum() internal view {
        uint256 assets = totalAssets();
        if (assets == 0) return;
        uint256 reserveBps = (currency.balanceOf(address(this)) * BPS_DENOM) / assets;
        if (reserveBps < minReserveBps) revert BelowReserveMinimum(reserveBps, minReserveBps);
    }
}
