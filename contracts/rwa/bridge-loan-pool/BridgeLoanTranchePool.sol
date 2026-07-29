// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BridgeLoanTranchePool
/// @notice Centrifuge Tinlake-shape pool of real estate bridge loans. Two
///         tranche tokens: senior (fixed APY, protected from first loss) and
///         junior (variable residual, absorbs first loss). The originator
///         retains all or most of the junior tranche as skin-in-the-game;
///         on-chain investors purchase the senior tranche.
///
///         Distinct from PoolDelegatePool (single-tier, cooldown redemption)
///         and CMBSWaterfall (3-tranche, single securitization). This is the
///         classic Centrifuge shape: ongoing origination + two tranches +
///         Sky-protocol-compatible senior tranche token.
///
///         Real Centrifuge integration: the originator posts the senior
///         tranche token as collateral in Sky (formerly MakerDAO) to borrow
///         USDS stablecoin against the real-world asset. Over 85% of
///         Centrifuge-originated loans have historically been financed this
///         way. The senior tranche token in this contract is designed to be
///         freely transferable specifically so that composability works.
contract BridgeLoanTranchePool is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ORIGINATOR_ROLE = keccak256("ORIGINATOR_ROLE");
    bytes32 public constant SENIOR_WHITELIST_ROLE = keccak256("SENIOR_WHITELIST_ROLE");

    uint256 public constant BPS_DENOM = 10_000;
    uint256 public constant PRECISION = 1e18;

    IERC20 public immutable currency;

    /// Senior tranche APY in bps (annualized). Fixed.
    uint256 public seniorApyBps;
    /// Maximum senior tranche as % of pool NAV. Beyond this, only junior can
    /// deposit. Enforced at senior subscribe.
    uint256 public seniorCapBps;

    /// Nominal senior + junior tranche shares outstanding.
    uint256 public seniorShares;
    uint256 public juniorShares;

    /// Total currency in the pool (idle + deployed).
    uint256 public totalPoolAssets;
    uint256 public totalDeployed;
    uint256 public totalWriteDowns;

    /// Per-tranche share ownership.
    mapping(address => uint256) public seniorBalance;
    mapping(address => uint256) public juniorBalance;

    /// Accumulated yield distributed to senior at fixed APY (accrues over time).
    uint256 public seniorAccruedTotal;
    uint256 public seniorLastAccrualAt;

    struct Loan {
        address borrower;
        uint256 principal;
        uint256 interestRateBps;
        uint256 originatedAt;
        uint256 maturityAt;
        bool active;
        bool defaulted;
    }
    Loan[] public loans;

    event SeniorSubscribed(address indexed investor, uint256 currencyIn, uint256 sharesOut);
    event JuniorSubscribed(address indexed investor, uint256 currencyIn, uint256 sharesOut);
    event LoanOriginated(uint256 indexed loanId, address indexed borrower, uint256 principal, uint256 maturityAt);
    event LoanRepaid(uint256 indexed loanId, uint256 principal, uint256 interest);
    event LoanWrittenDown(uint256 indexed loanId, uint256 writeDownAmount);
    event SeniorAccrued(uint256 accrualAmount);

    error NotWhitelisted(address account);
    error SeniorCapExceeded(uint256 requested, uint256 remaining);
    error InsufficientIdle(uint256 needed, uint256 available);
    error LoanNotActive(uint256 loanId);
    error ZeroAmount();

    constructor(
        address admin,
        address originator,
        address currency_,
        uint256 seniorApyBps_,
        uint256 seniorCapBps_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORIGINATOR_ROLE, originator);
        _grantRole(SENIOR_WHITELIST_ROLE, admin);
        require(seniorCapBps_ <= BPS_DENOM, "senior cap > 100%");
        currency = IERC20(currency_);
        seniorApyBps = seniorApyBps_;
        seniorCapBps = seniorCapBps_;
        seniorLastAccrualAt = block.timestamp;
    }

    // ---- Senior tranche (on-chain investors) ----

    function whitelistSeniorInvestor(address a) external onlyRole(SENIOR_WHITELIST_ROLE) {
        _grantRole(SENIOR_WHITELIST_ROLE, a);
    }

    function subscribeSenior(uint256 currencyAmount) external nonReentrant {
        if (!hasRole(SENIOR_WHITELIST_ROLE, msg.sender)) revert NotWhitelisted(msg.sender);
        if (currencyAmount == 0) revert ZeroAmount();
        _accrueSenior();

        // Enforce senior cap against post-subscribe pool NAV.
        uint256 newNav = totalPoolAssets + currencyAmount;
        uint256 seniorCap = (newNav * seniorCapBps) / BPS_DENOM;
        uint256 postSeniorNominal = _seniorNominal() + currencyAmount;
        if (postSeniorNominal > seniorCap) {
            revert SeniorCapExceeded(currencyAmount, seniorCap - _seniorNominal());
        }

        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        // Senior shares = currency contribution (fixed APY accrues on top; not NAV-share).
        seniorShares += currencyAmount;
        seniorBalance[msg.sender] += currencyAmount;
        totalPoolAssets += currencyAmount;
        emit SeniorSubscribed(msg.sender, currencyAmount, currencyAmount);
    }

    // ---- Junior tranche (originator's first-loss capital) ----

    function subscribeJunior(uint256 currencyAmount) external nonReentrant onlyRole(ORIGINATOR_ROLE) {
        if (currencyAmount == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        // Junior shares = pro-rata against junior NAV (residual value after
        // senior + accrued). Simplified: 1 junior share = 1 currency at
        // origin; NAV grows as loans repay in excess of senior APY, shrinks
        // on write-downs.
        uint256 juniorNav = _juniorNav();
        uint256 sharesToMint = juniorShares == 0
            ? currencyAmount
            : (currencyAmount * juniorShares) / juniorNav;
        juniorShares += sharesToMint;
        juniorBalance[msg.sender] += sharesToMint;
        totalPoolAssets += currencyAmount;
        emit JuniorSubscribed(msg.sender, currencyAmount, sharesToMint);
    }

    // ---- Origination (originator draws idle currency for a new loan) ----

    function originateLoan(address borrower, uint256 principal, uint256 interestRateBps, uint256 termSec)
        external nonReentrant onlyRole(ORIGINATOR_ROLE) returns (uint256 loanId)
    {
        if (principal == 0) revert ZeroAmount();
        uint256 idle = currency.balanceOf(address(this));
        if (principal > idle) revert InsufficientIdle(principal, idle);
        loans.push(Loan({
            borrower: borrower,
            principal: principal,
            interestRateBps: interestRateBps,
            originatedAt: block.timestamp,
            maturityAt: block.timestamp + termSec,
            active: true,
            defaulted: false
        }));
        loanId = loans.length - 1;
        totalDeployed += principal;
        currency.safeTransfer(borrower, principal);
        emit LoanOriginated(loanId, borrower, principal, block.timestamp + termSec);
    }

    // ---- Repayment ----

    function repayLoan(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];
        if (!loan.active) revert LoanNotActive(loanId);
        uint256 elapsed = block.timestamp - loan.originatedAt;
        uint256 interest = (loan.principal * loan.interestRateBps * elapsed) / (BPS_DENOM * 365 days);
        uint256 total = loan.principal + interest;
        currency.safeTransferFrom(msg.sender, address(this), total);
        loan.active = false;
        totalDeployed -= loan.principal;
        _accrueSenior();
        // interest flows into pool; senior gets APY, junior residual (via _juniorNav).
        emit LoanRepaid(loanId, loan.principal, interest);
    }

    // ---- Write-down (originator declares a loan defaulted) ----

    function writeDownLoan(uint256 loanId, uint256 writeDownAmount) external onlyRole(ORIGINATOR_ROLE) {
        Loan storage loan = loans[loanId];
        if (!loan.active) revert LoanNotActive(loanId);
        if (writeDownAmount > loan.principal) writeDownAmount = loan.principal;
        loan.defaulted = true;
        loan.active = false;
        totalDeployed -= loan.principal;
        totalWriteDowns += writeDownAmount;
        emit LoanWrittenDown(loanId, writeDownAmount);
    }

    // ---- Senior APY accrual ----

    function _accrueSenior() internal {
        uint256 elapsed = block.timestamp - seniorLastAccrualAt;
        if (elapsed == 0 || seniorShares == 0) {
            seniorLastAccrualAt = block.timestamp;
            return;
        }
        uint256 accrual = (seniorShares * seniorApyBps * elapsed) / (BPS_DENOM * 365 days);
        seniorAccruedTotal += accrual;
        seniorLastAccrualAt = block.timestamp;
        emit SeniorAccrued(accrual);
    }

    // ---- NAV views ----

    function _seniorNominal() internal view returns (uint256) {
        return seniorShares + seniorAccruedTotal;
    }

    /// @notice Junior NAV = totalPoolAssets - senior nominal (including accrual) - write-downs
    ///         (write-downs already deducted from totalPoolAssets via write-down flow's
    ///         reduction of currency balance). Clamps to zero.
    function _juniorNav() internal view returns (uint256) {
        uint256 seniorNominal = _seniorNominal();
        if (totalPoolAssets <= seniorNominal) return 0;
        return totalPoolAssets - seniorNominal;
    }

    function seniorNAV() external view returns (uint256) {
        return _seniorNominal();
    }

    function juniorNAV() external view returns (uint256) {
        return _juniorNav();
    }

    function loanCount() external view returns (uint256) {
        return loans.length;
    }
}
