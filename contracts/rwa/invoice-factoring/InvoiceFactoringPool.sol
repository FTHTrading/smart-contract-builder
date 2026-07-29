// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title InvoiceFactoringPool
/// @notice Short-term receivables pool in the Centrifuge shape. An originator
///         (typically a supply-chain finance provider or SME factoring firm)
///         registers invoices with a face value, due date, and debtor. The
///         pool advances a percentage (advance rate, typically 80-90%) to the
///         originator immediately. When the debtor pays, the pool receives
///         face value; the difference between face and advance funds the
///         yield to LP.
///
///         Simpler than PoolDelegatePool — invoices are self-liquidating
///         within 30-90 days, so no first-loss capital, no complex
///         concentration caps, and no cooldown redemptions (LPs redeem after
///         a fully-repaid pool cycle).
///
///         Reference deployments: Centrifuge Tinlake pools for supply-chain
///         finance, invoice factoring, and consumer credit.
contract InvoiceFactoringPool is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ORIGINATOR_ROLE = keccak256("ORIGINATOR_ROLE");
    bytes32 public constant LP_ROLE = keccak256("LP_ROLE");

    /// Basis points denominator.
    uint256 public constant BPS_DENOM = 10_000;

    IERC20 public immutable currency;
    /// Advance rate in bps of face value. e.g. 8_500 = 85% (LP advances 85%,
    /// receives 100% at maturity, spread = 15% is the yield).
    uint256 public immutable advanceRateBps;
    /// Max acceptable invoice tenor in seconds (e.g. 90 days).
    uint256 public immutable maxTenorSec;

    /// Total advanced across all outstanding invoices.
    uint256 public totalAdvanced;
    /// Sum of face values across all outstanding invoices.
    uint256 public totalFaceOutstanding;
    /// Sum of currency held by pool (available for new advances OR waiting for LP redemption).
    uint256 public totalIdle;
    /// LP contributions.
    mapping(address => uint256) public lpContribution;
    uint256 public totalLPContributions;
    /// Amount claimed by each LP (share of pool distributions).
    mapping(address => uint256) public lpClaimed;
    /// Total distributions made available to LPs.
    uint256 public totalDistributed;

    struct Invoice {
        address debtor;
        uint256 faceValue;
        uint256 advanced;
        uint256 dueDate;
        uint256 originatedAt;
        bool paid;
        bool written_off;
    }

    Invoice[] public invoices;

    event LPDeposit(address indexed lp, uint256 amount);
    event LPWithdraw(address indexed lp, uint256 amount);
    event InvoiceOriginated(uint256 indexed invoiceId, address indexed debtor, uint256 faceValue, uint256 advanced, uint256 dueDate);
    event InvoicePaid(uint256 indexed invoiceId, uint256 receivedAmount, uint256 yieldToLP);
    event InvoiceWrittenOff(uint256 indexed invoiceId, uint256 lossAmount);

    error ZeroAmount();
    error TenorTooLong(uint256 requested, uint256 max);
    error InsufficientPoolLiquidity(uint256 needed, uint256 available);
    error InvoiceAlreadyClosed(uint256 invoiceId);
    error NoClaim(address lp);
    error NotWhitelisted(address lp);

    constructor(
        address admin,
        address originator,
        address currency_,
        uint256 advanceRateBps_,
        uint256 maxTenorSec_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORIGINATOR_ROLE, originator);
        currency = IERC20(currency_);
        require(advanceRateBps_ > 0 && advanceRateBps_ <= BPS_DENOM, "advance rate 0-100%");
        advanceRateBps = advanceRateBps_;
        maxTenorSec = maxTenorSec_;
    }

    function whitelistLP(address lp) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LP_ROLE, lp);
    }
    function removeLP(address lp) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(LP_ROLE, lp);
    }

    // ---- LP flow ----

    function lpDeposit(uint256 amount) external nonReentrant {
        if (!hasRole(LP_ROLE, msg.sender)) revert NotWhitelisted(msg.sender);
        if (amount == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), amount);
        lpContribution[msg.sender] += amount;
        totalLPContributions += amount;
        totalIdle += amount;
        emit LPDeposit(msg.sender, amount);
    }

    /// @notice LP withdraws their pro-rata share of pool distributions.
    ///         Formula: entitled = lpContribution * totalDistributed / totalLPContributions
    ///         Distributions grow as invoices are paid (yield hits the pool).
    ///         LP may not withdraw their principal contribution until the
    ///         pool has liquid balance ≥ principal (i.e. all their-share of
    ///         active invoices have matured).
    function lpClaim() external nonReentrant {
        if (totalLPContributions == 0) revert NoClaim(msg.sender);
        uint256 entitled = (lpContribution[msg.sender] * totalDistributed) / totalLPContributions;
        uint256 due = entitled - lpClaimed[msg.sender];
        if (due == 0) revert NoClaim(msg.sender);
        if (due > totalIdle) revert InsufficientPoolLiquidity(due, totalIdle);
        lpClaimed[msg.sender] += due;
        totalIdle -= due;
        currency.safeTransfer(msg.sender, due);
        emit LPWithdraw(msg.sender, due);
    }

    // ---- Originator flow ----

    function originateInvoice(
        address debtor,
        uint256 faceValue,
        uint256 dueDate
    ) external nonReentrant onlyRole(ORIGINATOR_ROLE) returns (uint256 invoiceId) {
        if (faceValue == 0) revert ZeroAmount();
        if (dueDate <= block.timestamp) revert TenorTooLong(0, maxTenorSec);
        uint256 tenor = dueDate - block.timestamp;
        if (tenor > maxTenorSec) revert TenorTooLong(tenor, maxTenorSec);

        uint256 advanceAmount = (faceValue * advanceRateBps) / BPS_DENOM;
        if (advanceAmount > totalIdle) revert InsufficientPoolLiquidity(advanceAmount, totalIdle);

        invoices.push(Invoice({
            debtor: debtor,
            faceValue: faceValue,
            advanced: advanceAmount,
            dueDate: dueDate,
            originatedAt: block.timestamp,
            paid: false,
            written_off: false
        }));
        invoiceId = invoices.length - 1;

        totalIdle -= advanceAmount;
        totalAdvanced += advanceAmount;
        totalFaceOutstanding += faceValue;
        currency.safeTransfer(msg.sender, advanceAmount);
        emit InvoiceOriginated(invoiceId, debtor, faceValue, advanceAmount, dueDate);
    }

    /// @notice Debtor (or originator on the debtor's behalf) pays the invoice
    ///         at face value. Pool receives face; yield = face - advanced.
    function payInvoice(uint256 invoiceId) external nonReentrant {
        Invoice storage inv = invoices[invoiceId];
        if (inv.paid || inv.written_off) revert InvoiceAlreadyClosed(invoiceId);
        currency.safeTransferFrom(msg.sender, address(this), inv.faceValue);
        inv.paid = true;
        totalIdle += inv.faceValue;
        totalAdvanced -= inv.advanced;
        totalFaceOutstanding -= inv.faceValue;
        uint256 yieldEarned = inv.faceValue - inv.advanced;
        totalDistributed += yieldEarned;
        emit InvoicePaid(invoiceId, inv.faceValue, yieldEarned);
    }

    /// @notice Originator marks an invoice as defaulted. Pool absorbs the
    ///         write-down; LP entitlements shrink proportionally.
    ///         In a production Centrifuge shape, a first-loss junior tranche
    ///         absorbs first. This simplified pool has no junior tranche;
    ///         the tranche layer is a follow-up.
    function writeOffInvoice(uint256 invoiceId) external onlyRole(ORIGINATOR_ROLE) {
        Invoice storage inv = invoices[invoiceId];
        if (inv.paid || inv.written_off) revert InvoiceAlreadyClosed(invoiceId);
        inv.written_off = true;
        totalAdvanced -= inv.advanced;
        totalFaceOutstanding -= inv.faceValue;
        emit InvoiceWrittenOff(invoiceId, inv.advanced);
    }

    function invoiceCount() external view returns (uint256) {
        return invoices.length;
    }
    function poolBalance() external view returns (uint256 idle, uint256 advanced, uint256 faceOutstanding) {
        return (totalIdle, totalAdvanced, totalFaceOutstanding);
    }
}
