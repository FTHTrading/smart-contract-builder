// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEligibilityCheck {
    function eligibleFor(address holder, uint256[] calldata requiredClaims) external view returns (bool);
}

/// @title RealEstateDebtToken
/// @notice Fungible ERC-20 claim on a single mortgage or HELOC. Reference
///         shape: Figure Technology Solutions' tokenized mortgages on
///         Provenance Blockchain — $18B+ represented value, primarily HELOCs
///         and residential mortgages.
///
///         The token represents a pro-rata interest in the loan's cash flows.
///         Servicer collects monthly principal + interest from the borrower
///         off-chain, then deposits the currency into this contract.
///         Distributions flow to token holders via the accumulator pattern.
///
///         Token holders are US-restricted by default (mortgage debt claims
///         are securities under Reg D). Set required claim topics to
///         [1 = KYC, 2 = accredited] for a Reg D 506(c) issuance. For
///         non-US retail, remove claim topic 3 (US jurisdiction gate).
///
///         Loan-level metadata (origination principal, rate, term,
///         amortization schedule) is stored on-chain for the audit trail;
///         the physical mortgage note remains the operative legal instrument.
contract RealEstateDebtToken is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SERVICER_ROLE = keccak256("SERVICER_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    uint256 public constant PRECISION = 1e18;

    IERC20 public immutable currency;
    IEligibilityCheck public immutable eligibilityRegistry;

    // ---- Loan-level metadata (immutable at issuance) ----
    uint256 public immutable originalPrincipal;
    uint256 public immutable interestRateBps;      // annualized
    uint256 public immutable termMonths;
    uint256 public immutable originatedAt;
    /// keccak256 of the executed mortgage note. The physical note is the
    /// operative legal instrument; the hash on-chain proves the note exists.
    bytes32 public immutable mortgageNoteHash;
    /// keccak256 of the property deed / title report. Same evidentiary role.
    bytes32 public immutable propertyDeedHash;
    /// keccak256 of the property address string (for privacy — the address
    /// itself is not committed on-chain, but the hash proves whoever holds
    /// the underlying record has the same address on file).
    bytes32 public immutable propertyAddressHash;

    // ---- Servicing state ----
    uint256 public totalPrincipalPaid;
    uint256 public totalInterestPaid;
    uint256 public lastPaymentAt;
    bool public defaulted;

    // ---- Distribution accumulator ----
    uint256 public accCurrencyPerShare;
    mapping(address => uint256) public debtCursor;
    mapping(address => uint256) public pendingReward;

    uint256[] private _requiredClaims;

    event ServicingDeposit(uint256 amount, uint256 principalPortion, uint256 interestPortion, uint256 newAccPerShare);
    event Claimed(address indexed holder, uint256 amount);
    event LoanDefaulted(uint256 outstandingPrincipal);
    event RequiredClaimsUpdated(uint256[] claims);

    error ReceiverNotEligible(address receiver);
    error NoUnclaimed();
    error LoanAlreadyDefaulted();
    error ZeroAmount();

    struct InitParams {
        string name;
        string symbol;
        address admin;
        address issuer;
        address servicer;
        address currency;
        address eligibility;
        uint256[] requiredClaims;
        uint256 originalPrincipal;
        uint256 interestRateBps;
        uint256 termMonths;
        bytes32 mortgageNoteHash;
        bytes32 propertyDeedHash;
        bytes32 propertyAddressHash;
    }

    constructor(InitParams memory p) ERC20(p.name, p.symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(ISSUER_ROLE, p.issuer);
        _grantRole(SERVICER_ROLE, p.servicer);
        currency = IERC20(p.currency);
        eligibilityRegistry = IEligibilityCheck(p.eligibility);
        _requiredClaims = p.requiredClaims;
        originalPrincipal = p.originalPrincipal;
        interestRateBps = p.interestRateBps;
        termMonths = p.termMonths;
        originatedAt = block.timestamp;
        mortgageNoteHash = p.mortgageNoteHash;
        propertyDeedHash = p.propertyDeedHash;
        propertyAddressHash = p.propertyAddressHash;
    }

    // ---- Issuance (issuer mints shares to investors during offering) ----

    function mint(address to, uint256 shares) external onlyRole(ISSUER_ROLE) {
        _mint(to, shares);
    }

    // ---- Transfer eligibility ----

    function _update(address from, address to, uint256 value) internal override {
        if (to != address(0)) {
            if (!eligibilityRegistry.eligibleFor(to, _requiredClaims)) {
                revert ReceiverNotEligible(to);
            }
        }
        if (from != address(0)) _accrue(from);
        if (to != address(0) && to != from) _accrue(to);
        super._update(from, to, value);
    }

    // ---- Servicing (servicer deposits monthly principal + interest) ----

    /// @notice Servicer records a payment received from the mortgage borrower.
    ///         Split between principal + interest is provided by the servicer
    ///         from their amortization schedule (this contract does NOT
    ///         compute amortization — that's the servicer's system of record).
    function recordPayment(uint256 principalPortion, uint256 interestPortion) external nonReentrant onlyRole(SERVICER_ROLE) {
        if (defaulted) revert LoanAlreadyDefaulted();
        uint256 total = principalPortion + interestPortion;
        if (total == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), total);
        totalPrincipalPaid += principalPortion;
        totalInterestPaid += interestPortion;
        lastPaymentAt = block.timestamp;
        uint256 supply = totalSupply();
        if (supply > 0) {
            accCurrencyPerShare += (total * PRECISION) / supply;
        }
        emit ServicingDeposit(total, principalPortion, interestPortion, accCurrencyPerShare);
    }

    function _accrue(address holder) internal {
        uint256 bal = balanceOf(holder);
        uint256 owed = (bal * (accCurrencyPerShare - debtCursor[holder])) / PRECISION;
        if (owed > 0) pendingReward[holder] += owed;
        debtCursor[holder] = accCurrencyPerShare;
    }

    function claimable(address holder) public view returns (uint256) {
        uint256 bal = balanceOf(holder);
        uint256 owed = (bal * (accCurrencyPerShare - debtCursor[holder])) / PRECISION;
        return pendingReward[holder] + owed;
    }

    function claim() external nonReentrant {
        _accrue(msg.sender);
        uint256 due = pendingReward[msg.sender];
        if (due == 0) revert NoUnclaimed();
        pendingReward[msg.sender] = 0;
        currency.safeTransfer(msg.sender, due);
        emit Claimed(msg.sender, due);
    }

    // ---- Default ----

    function declareDefault() external onlyRole(SERVICER_ROLE) {
        if (defaulted) revert LoanAlreadyDefaulted();
        defaulted = true;
        uint256 outstanding = originalPrincipal > totalPrincipalPaid
            ? originalPrincipal - totalPrincipalPaid
            : 0;
        emit LoanDefaulted(outstanding);
    }

    // ---- Admin ----

    function setRequiredClaims(uint256[] calldata claims) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete _requiredClaims;
        for (uint256 i = 0; i < claims.length; i++) _requiredClaims.push(claims[i]);
        emit RequiredClaimsUpdated(claims);
    }
    function requiredClaims() external view returns (uint256[] memory) {
        return _requiredClaims;
    }

    function outstandingPrincipal() external view returns (uint256) {
        if (originalPrincipal < totalPrincipalPaid) return 0;
        return originalPrincipal - totalPrincipalPaid;
    }
}
