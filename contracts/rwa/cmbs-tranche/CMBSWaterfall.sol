// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CMBSWaterfall
/// @notice Three-tranche distribution: senior debt gets paid first up to its
///         entitlement (principal + accrued interest), then mezzanine, then
///         equity residual. Investors in each tranche pull their share of what
///         the waterfall allocated to their tranche.
///
///         Interest accrues by simple period-multiplied rate (no compounding
///         inside the contract — periods are month-length in production, and
///         the accountant handles the compounding math off-chain if needed).
contract CMBSWaterfall is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SPONSOR_ROLE = keccak256("SPONSOR_ROLE");

    /// Basis points denominator. 10_000 = 100%.
    uint256 public constant BPS_DENOM = 10_000;

    IERC20 public immutable currency;

    struct Tranche {
        /// Sum of all investor contributions to this tranche.
        uint256 principalDeposited;
        /// Principal still outstanding (deposited - repaid).
        uint256 principalOutstanding;
        /// Accrued but unpaid interest.
        uint256 accruedInterest;
        /// Total interest paid to date across all holders in this tranche.
        uint256 totalInterestPaid;
        /// Annual rate in bps (e.g. 700 = 7%).
        uint256 rateBps;
        /// Last block.timestamp at which interest was accrued.
        uint256 lastAccrualAt;
        /// Per-investor principal contributions.
        mapping(address => uint256) contribution;
        /// Per-investor amount claimed to date.
        mapping(address => uint256) claimed;
        /// Per-investor entitlement pool (grows as waterfall allocates).
        mapping(address => uint256) entitlement;
    }

    /// 0 = senior, 1 = mezz, 2 = equity.
    Tranche[3] public tranches;

    event ContributionRecorded(uint256 indexed trancheIdx, address indexed investor, uint256 amount);
    event Deposited(uint256 indexed depositId, uint256 amount, uint256 toSenior, uint256 toMezz, uint256 toEquity);
    event Claimed(uint256 indexed trancheIdx, address indexed investor, uint256 amount);
    event InterestAccrued(uint256 indexed trancheIdx, uint256 amount);

    error InvalidTranche(uint256 idx);
    error NoEntitlement(uint256 trancheIdx, address investor);
    error TrancheClosed(uint256 trancheIdx);
    error ZeroAmount();

    uint256 public depositCount;

    constructor(
        address admin,
        address sponsor,
        address currency_,
        uint256[3] memory rateBps
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SPONSOR_ROLE, sponsor);
        currency = IERC20(currency_);
        for (uint256 i = 0; i < 3; i++) {
            tranches[i].rateBps = rateBps[i];
            tranches[i].lastAccrualAt = block.timestamp;
        }
    }

    /// @notice Admin records an investor's off-chain contribution to a tranche.
    ///         For on-chain funding, use fund() (still contribution accounting).
    function recordContribution(uint256 trancheIdx, address investor, uint256 amount)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (trancheIdx > 2) revert InvalidTranche(trancheIdx);
        if (amount == 0) revert ZeroAmount();
        Tranche storage t = tranches[trancheIdx];
        t.contribution[investor] += amount;
        t.principalDeposited += amount;
        t.principalOutstanding += amount;
        emit ContributionRecorded(trancheIdx, investor, amount);
    }

    /// @notice Investor sends currency into a tranche. Records their
    ///         contribution and increases principal outstanding.
    function fund(uint256 trancheIdx, uint256 amount) external nonReentrant {
        if (trancheIdx > 2) revert InvalidTranche(trancheIdx);
        if (amount == 0) revert ZeroAmount();
        Tranche storage t = tranches[trancheIdx];
        currency.safeTransferFrom(msg.sender, address(this), amount);
        t.contribution[msg.sender] += amount;
        t.principalDeposited += amount;
        t.principalOutstanding += amount;
        emit ContributionRecorded(trancheIdx, msg.sender, amount);
    }

    /// @notice Accrue interest on all tranches based on time elapsed. Callable
    ///         by anyone (safe — no side effects other than updating accrued).
    function accrueAll() public {
        for (uint256 i = 0; i < 3; i++) {
            _accrue(i);
        }
    }

    function _accrue(uint256 idx) internal {
        Tranche storage t = tranches[idx];
        uint256 elapsed = block.timestamp - t.lastAccrualAt;
        if (elapsed == 0 || t.principalOutstanding == 0 || t.rateBps == 0) {
            t.lastAccrualAt = block.timestamp;
            return;
        }
        // interest = principal * rate * elapsed / (BPS_DENOM * 365 days)
        uint256 interest = (t.principalOutstanding * t.rateBps * elapsed) / (BPS_DENOM * 365 days);
        t.accruedInterest += interest;
        t.lastAccrualAt = block.timestamp;
        emit InterestAccrued(idx, interest);
    }

    /// @notice Sponsor deposits waterfall funds. Runs the cascade:
    ///         1. Fill senior's accrued interest
    ///         2. Repay senior principal
    ///         3. Fill mezz's accrued interest
    ///         4. Repay mezz principal
    ///         5. Everything left → equity
    ///
    ///         Investor entitlements are updated pro-rata within each tranche
    ///         based on their contribution share.
    function distribute(uint256 amount) external nonReentrant onlyRole(SPONSOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), amount);
        accrueAll();

        uint256 remaining = amount;
        uint256 depositId = depositCount++;

        uint256 toSenior = _payTranche(0, remaining);
        remaining -= toSenior;
        uint256 toMezz = _payTranche(1, remaining);
        remaining -= toMezz;
        // Equity gets whatever's left, regardless of accrued/principal.
        Tranche storage eq = tranches[2];
        if (remaining > 0 && eq.principalDeposited > 0) {
            _allocatePro(2, remaining);
        }
        emit Deposited(depositId, amount, toSenior, toMezz, remaining);
    }

    /// @dev Pay interest then principal for one tranche. Returns amount consumed.
    function _payTranche(uint256 idx, uint256 available) internal returns (uint256 consumed) {
        Tranche storage t = tranches[idx];
        if (available == 0 || t.principalDeposited == 0) return 0;

        uint256 interestPay = t.accruedInterest;
        if (interestPay > available) interestPay = available;
        t.accruedInterest -= interestPay;
        t.totalInterestPaid += interestPay;
        _allocatePro(idx, interestPay);
        consumed += interestPay;
        available -= interestPay;

        if (available == 0 || t.principalOutstanding == 0) return consumed;

        uint256 principalPay = t.principalOutstanding;
        if (principalPay > available) principalPay = available;
        t.principalOutstanding -= principalPay;
        _allocatePro(idx, principalPay);
        consumed += principalPay;
    }

    /// @dev Allocate the amount to a tranche's investor entitlement map,
    ///      pro-rata by contribution share. Investors call claim() to pull.
    ///      (This is O(N holders) as written — production replaces the
    ///      distribution loop with a snapshot-based per-share accumulator
    ///      like MasterChef; kept naive here for readability.)
    function _allocatePro(uint256 idx, uint256 amount) internal {
        Tranche storage t = tranches[idx];
        if (amount == 0 || t.principalDeposited == 0) return;
        // NOTE: this contract keeps a running per-investor entitlement that
        // grows as distributions happen. See claim() below. For a full
        // production deployment with many holders, switch to a per-share
        // accumulator (rewardPerShare) — same math, O(1) per allocation.
        // For 3-tranche SPV debt with <20 investors per tranche, the naive
        // model here is fine and much easier to audit.
        //
        // Since we cannot iterate the mapping, we track an accumulator per
        // tranche and each holder pulls their pro-rata slice at claim time
        // based on their share of principalDeposited.
        t.entitlement[address(0)] += amount; // sentinel key for the accumulator
    }

    function claimable(uint256 trancheIdx, address investor) public view returns (uint256) {
        if (trancheIdx > 2) revert InvalidTranche(trancheIdx);
        Tranche storage t = tranches[trancheIdx];
        if (t.principalDeposited == 0 || t.contribution[investor] == 0) return 0;
        uint256 totalAllocated = t.entitlement[address(0)];
        uint256 entitled = (totalAllocated * t.contribution[investor]) / t.principalDeposited;
        if (entitled <= t.claimed[investor]) return 0;
        return entitled - t.claimed[investor];
    }

    function claim(uint256 trancheIdx) external nonReentrant {
        uint256 due = claimable(trancheIdx, msg.sender);
        if (due == 0) revert NoEntitlement(trancheIdx, msg.sender);
        Tranche storage t = tranches[trancheIdx];
        t.claimed[msg.sender] += due;
        currency.safeTransfer(msg.sender, due);
        emit Claimed(trancheIdx, msg.sender, due);
    }

    function contributionOf(uint256 trancheIdx, address investor) external view returns (uint256) {
        return tranches[trancheIdx].contribution[investor];
    }
    function claimedOf(uint256 trancheIdx, address investor) external view returns (uint256) {
        return tranches[trancheIdx].claimed[investor];
    }
}
