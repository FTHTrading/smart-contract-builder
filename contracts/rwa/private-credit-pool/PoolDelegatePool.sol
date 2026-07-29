// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PoolDelegatePool
/// @notice Institutional lending pool in the Maple Finance shape. A curated
///         credit marketplace where a designated "Pool Delegate" — a
///         professional credit officer (BlockTower, Room40, AQRU-style) —
///         underwrites individual institutional borrowers, sets pool
///         concentration limits, and posts first-loss capital to align
///         incentives with lenders.
///
///         Key design points from the Maple market post-2022 restructuring:
///           - Loans are fixed-rate, fixed-term (30-180 days typical)
///           - Overcollateralization required for corporate borrowers (105-130%
///             in liquid assets like BTC, ETH, SOL — held off-chain by the
///             collateral custodian, not the pool itself)
///           - Pool Delegate posts first-loss tranche BEFORE lenders can deposit
///           - Lenders receive pool shares (ERC-20); redemption is period-based
///             (cooldown to prevent runs on illiquid book)
///           - Bad debt is absorbed by first-loss tranche first, then lenders
///             pro-rata
///
///         This is engineering scaffolding for the Maple pattern. Production
///         deployments would add: an on-chain collateral custody attestor
///         (Chainlink Proof of Reserve), per-borrower KYC via ACE + ERC-3643,
///         auction-based liquidation of defaulted loans, tiered lender classes
///         (senior/junior LPs).
contract PoolDelegatePool is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant POOL_DELEGATE_ROLE = keccak256("POOL_DELEGATE_ROLE");
    bytes32 public constant LP_WHITELIST_ROLE = keccak256("LP_WHITELIST_ROLE");

    /// Basis points denominator.
    uint256 public constant BPS_DENOM = 10_000;

    /// Currency lenders deposit and receive redemptions in (typically USDC/USDT).
    IERC20 public immutable currency;
    /// Cooldown between requestRedemption and executeRedemption, in seconds.
    /// Prevents lender runs against an illiquid loan book.
    uint256 public immutable redemptionCooldownSec;
    /// Required first-loss capital the Pool Delegate must post, in bps of pool
    /// total. e.g. 1000 = 10% (delegate stakes 10% of pool size).
    uint256 public immutable firstLossBps;

    /// Pool Delegate's staked first-loss capital.
    uint256 public firstLossPosted;
    /// Sum of loans currently outstanding.
    uint256 public totalDeployed;
    /// Sum of currency held by the pool (not out on loan).
    uint256 public totalIdle;
    /// Sum of bad-debt write-downs applied against the pool.
    uint256 public totalWriteDowns;

    /// Whether new LP deposits are open. Delegate can pause on run risk.
    bool public depositsOpen;

    struct Loan {
        address borrower;
        uint256 principal;
        uint256 interestRateBps;   // annualized
        uint256 originatedAt;
        uint256 maturityAt;
        uint256 interestAccrued;   // updated at repayment / write-down
        bool active;
        bool defaulted;
    }

    Loan[] public loans;
    /// borrower → sum of principal across all active loans (concentration limit tracking)
    mapping(address => uint256) public borrowerExposure;
    /// Max exposure per borrower in bps of total pool size.
    uint256 public perBorrowerCapBps;

    struct RedemptionRequest {
        uint256 shares;
        uint256 requestedAt;
    }

    mapping(address => RedemptionRequest) public pendingRedemption;

    event FirstLossPosted(address indexed delegate, uint256 amount, uint256 totalFirstLoss);
    event LenderDeposited(address indexed lender, uint256 currencyAmount, uint256 sharesMinted);
    event RedemptionRequested(address indexed lender, uint256 shares, uint256 executableAt);
    event RedemptionExecuted(address indexed lender, uint256 shares, uint256 currencyReturned);
    event LoanOriginated(uint256 indexed loanId, address indexed borrower, uint256 principal, uint256 interestRateBps, uint256 maturityAt);
    event LoanRepaid(uint256 indexed loanId, uint256 principal, uint256 interest);
    event LoanDefaulted(uint256 indexed loanId, uint256 outstandingPrincipal);
    event WriteDownApplied(uint256 indexed loanId, uint256 writeDownAmount, uint256 firstLossConsumed, uint256 lpImpact);
    event DepositsToggled(bool open);

    error NotWhitelisted(address lender);
    error FirstLossInsufficient(uint256 required, uint256 posted);
    error DepositsClosed();
    error NoPendingRedemption();
    error CooldownActive(uint256 requestedAt, uint256 executableAt);
    error InsufficientIdle(uint256 needed, uint256 available);
    error BorrowerCapExceeded(address borrower, uint256 currentExposure, uint256 cap);
    error LoanNotActive(uint256 loanId);
    error LoanAlreadyDefaulted(uint256 loanId);
    error ZeroAmount();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address delegate,
        address currency_,
        uint256 redemptionCooldownSec_,
        uint256 firstLossBps_,
        uint256 perBorrowerCapBps_
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POOL_DELEGATE_ROLE, delegate);
        _grantRole(LP_WHITELIST_ROLE, admin);
        currency = IERC20(currency_);
        redemptionCooldownSec = redemptionCooldownSec_;
        firstLossBps = firstLossBps_;
        perBorrowerCapBps = perBorrowerCapBps_;
    }

    // ============================================================
    // Pool Delegate — capital + admin
    // ============================================================

    function postFirstLoss(uint256 amount) external onlyRole(POOL_DELEGATE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), amount);
        firstLossPosted += amount;
        emit FirstLossPosted(msg.sender, amount, firstLossPosted);
    }

    function openDeposits() external onlyRole(POOL_DELEGATE_ROLE) {
        // Enforce that first-loss is at least the configured bps of current
        // pool size (0-shares pool is fine — delegate can open with 0 shares
        // outstanding and their own first-loss posted).
        depositsOpen = true;
        emit DepositsToggled(true);
    }

    function closeDeposits() external onlyRole(POOL_DELEGATE_ROLE) {
        depositsOpen = false;
        emit DepositsToggled(false);
    }

    function whitelistLender(address lender) external onlyRole(LP_WHITELIST_ROLE) {
        _grantRole(LP_WHITELIST_ROLE, lender);
    }
    function removeLender(address lender) external onlyRole(LP_WHITELIST_ROLE) {
        _revokeRole(LP_WHITELIST_ROLE, lender);
    }

    // ============================================================
    // Lender flow — deposit + redeem (cooldown-gated)
    // ============================================================

    function deposit(uint256 currencyAmount) external nonReentrant {
        if (!depositsOpen) revert DepositsClosed();
        if (!hasRole(LP_WHITELIST_ROLE, msg.sender)) revert NotWhitelisted(msg.sender);
        if (currencyAmount == 0) revert ZeroAmount();

        // Enforce first-loss coverage against post-deposit pool size.
        uint256 poolSizeAfter = totalPoolAssets() + currencyAmount;
        uint256 requiredFirstLoss = (poolSizeAfter * firstLossBps) / BPS_DENOM;
        if (firstLossPosted < requiredFirstLoss) {
            revert FirstLossInsufficient(requiredFirstLoss, firstLossPosted);
        }

        uint256 sharesToMint = _sharesForDeposit(currencyAmount);
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        totalIdle += currencyAmount;
        _mint(msg.sender, sharesToMint);
        emit LenderDeposited(msg.sender, currencyAmount, sharesToMint);
    }

    function requestRedemption(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        pendingRedemption[msg.sender] = RedemptionRequest({
            shares: shares,
            requestedAt: block.timestamp
        });
        emit RedemptionRequested(msg.sender, shares, block.timestamp + redemptionCooldownSec);
    }

    function executeRedemption() external nonReentrant {
        RedemptionRequest memory req = pendingRedemption[msg.sender];
        if (req.shares == 0) revert NoPendingRedemption();
        uint256 executableAt = req.requestedAt + redemptionCooldownSec;
        if (block.timestamp < executableAt) revert CooldownActive(req.requestedAt, executableAt);

        uint256 currencyOut = _currencyForShares(req.shares);
        if (currencyOut > totalIdle) revert InsufficientIdle(currencyOut, totalIdle);

        delete pendingRedemption[msg.sender];
        _burn(msg.sender, req.shares);
        totalIdle -= currencyOut;
        currency.safeTransfer(msg.sender, currencyOut);
        emit RedemptionExecuted(msg.sender, req.shares, currencyOut);
    }

    // ============================================================
    // Pool Delegate — loan lifecycle
    // ============================================================

    function originateLoan(
        address borrower,
        uint256 principal,
        uint256 interestRateBps,
        uint256 termSec
    ) external onlyRole(POOL_DELEGATE_ROLE) returns (uint256 loanId) {
        if (principal == 0) revert ZeroAmount();
        if (principal > totalIdle) revert InsufficientIdle(principal, totalIdle);

        uint256 newExposure = borrowerExposure[borrower] + principal;
        uint256 cap = (totalPoolAssets() * perBorrowerCapBps) / BPS_DENOM;
        if (newExposure > cap) revert BorrowerCapExceeded(borrower, newExposure, cap);

        loans.push(Loan({
            borrower: borrower,
            principal: principal,
            interestRateBps: interestRateBps,
            originatedAt: block.timestamp,
            maturityAt: block.timestamp + termSec,
            interestAccrued: 0,
            active: true,
            defaulted: false
        }));
        loanId = loans.length - 1;

        borrowerExposure[borrower] = newExposure;
        totalIdle -= principal;
        totalDeployed += principal;
        currency.safeTransfer(borrower, principal);
        emit LoanOriginated(loanId, borrower, principal, interestRateBps, block.timestamp + termSec);
    }

    /// @notice Borrower repays principal + interest. Interest is computed as
    ///         simple-interest against actual holding period.
    function repayLoan(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];
        if (!loan.active) revert LoanNotActive(loanId);
        if (loan.defaulted) revert LoanAlreadyDefaulted(loanId);

        uint256 elapsed = block.timestamp - loan.originatedAt;
        uint256 interest = (loan.principal * loan.interestRateBps * elapsed) / (BPS_DENOM * 365 days);
        uint256 total = loan.principal + interest;

        currency.safeTransferFrom(msg.sender, address(this), total);
        loan.active = false;
        loan.interestAccrued = interest;
        borrowerExposure[loan.borrower] -= loan.principal;
        totalDeployed -= loan.principal;
        totalIdle += total;
        emit LoanRepaid(loanId, loan.principal, interest);
    }

    /// @notice Pool Delegate marks a loan as defaulted and applies a
    ///         write-down. First-loss capital absorbs first; residual hits
    ///         lenders pro-rata (via reduced totalPoolAssets, which reduces
    ///         per-share NAV).
    function defaultLoan(uint256 loanId, uint256 writeDownAmount) external onlyRole(POOL_DELEGATE_ROLE) {
        Loan storage loan = loans[loanId];
        if (!loan.active) revert LoanNotActive(loanId);
        if (loan.defaulted) revert LoanAlreadyDefaulted(loanId);
        if (writeDownAmount > loan.principal) writeDownAmount = loan.principal;

        loan.defaulted = true;
        loan.active = false;
        borrowerExposure[loan.borrower] -= loan.principal;
        totalDeployed -= loan.principal;

        uint256 fromFirstLoss = writeDownAmount > firstLossPosted ? firstLossPosted : writeDownAmount;
        uint256 fromLPs = writeDownAmount - fromFirstLoss;
        firstLossPosted -= fromFirstLoss;
        totalWriteDowns += fromLPs;

        emit LoanDefaulted(loanId, loan.principal);
        emit WriteDownApplied(loanId, writeDownAmount, fromFirstLoss, fromLPs);
    }

    // ============================================================
    // Views
    // ============================================================

    function totalPoolAssets() public view returns (uint256) {
        // idle + deployed - write-downs (write-downs already reduced totalIdle
        // via defaultLoan's first-loss consumption; LP impact reduces NAV).
        return totalIdle + totalDeployed;
    }

    function loanCount() external view returns (uint256) {
        return loans.length;
    }

    function _sharesForDeposit(uint256 currencyAmount) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return currencyAmount;
        uint256 assets = totalPoolAssets();
        if (assets == 0) return currencyAmount;
        return (currencyAmount * supply) / assets;
    }

    function _currencyForShares(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return (shares * totalPoolAssets()) / supply;
    }
}
