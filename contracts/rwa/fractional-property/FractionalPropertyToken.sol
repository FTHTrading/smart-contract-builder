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

/// @title FractionalPropertyToken
/// @notice Fungible fractional equity in a single property held by an SPV.
///         Reference shape: RealT and Lofty — U.S. residential properties
///         (primarily Midwest) tokenized as SPV shares, sold to non-U.S.
///         retail under Regulation S, with daily rental income distributed
///         in USDC to token holders.
///
///         Key operational cycle:
///           1. Sponsor forms a Delaware LLC that legally owns the property
///           2. LLC issues fractional membership interests, tokenized as
///              this ERC-20
///           3. Property manager collects rent off-chain, deposits net income
///              (after property tax, insurance, maintenance reserves) into
///              this contract at configured cadence (daily, weekly, monthly)
///           4. Token holders claim their pro-rata share via accumulator pattern
///           5. On property sale, sponsor deposits sale proceeds; holders
///              redeem their tokens for pro-rata cash and the contract retires
///
///         Regulatory posture: securities under any jurisdiction that
///         classifies fractional real estate ownership as such. RealT's
///         production model restricts to non-U.S. retail via Reg S; other
///         issuers use Reg D 506(c) for U.S. accredited investors. Set
///         required claim topics accordingly.
contract FractionalPropertyToken is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PROPERTY_MANAGER_ROLE = keccak256("PROPERTY_MANAGER_ROLE");
    bytes32 public constant SPONSOR_ROLE = keccak256("SPONSOR_ROLE");

    uint256 public constant PRECISION = 1e18;

    IERC20 public immutable currency;
    IEligibilityCheck public immutable eligibilityRegistry;
    uint256[] private _requiredClaims;

    // ---- Property metadata ----
    /// keccak256 of the property address (privacy — address is not committed).
    bytes32 public immutable propertyAddressHash;
    /// Total valuation at issuance in currency units.
    uint256 public immutable initialValuationCurrency;
    /// keccak256 of the property deed / title report.
    bytes32 public immutable propertyDeedHash;
    /// keccak256 of the SPV's Articles of Organization / Operating Agreement.
    bytes32 public immutable spvFormationDocHash;

    // ---- Distribution accumulator (rental income) ----
    uint256 public accCurrencyPerShare;
    uint256 public totalDistributed;
    mapping(address => uint256) public debtCursor;
    mapping(address => uint256) public pendingReward;

    // ---- Sale-of-property redemption ----
    bool public soldFlag;
    uint256 public salePoolPerShare; // scaled by PRECISION, set once at sale
    mapping(address => bool) public redeemedFromSale;

    event RentalDeposited(address indexed manager, uint256 amount, uint256 newAccPerShare);
    event Claimed(address indexed holder, uint256 amount);
    event PropertySold(uint256 saleProceeds, uint256 supplyAtSale, uint256 salePoolPerShare);
    event RedeemedFromSale(address indexed holder, uint256 shares, uint256 currencyOut);
    event RequiredClaimsUpdated(uint256[] claims);

    error ReceiverNotEligible(address receiver);
    error NoUnclaimed();
    error AlreadySold();
    error NotYetSold();
    error AlreadyRedeemed();
    error ZeroAmount();

    struct InitParams {
        string name;
        string symbol;
        address admin;
        address sponsor;
        address propertyManager;
        address currency;
        address eligibility;
        uint256[] requiredClaims;
        uint256 initialValuationCurrency;
        bytes32 propertyAddressHash;
        bytes32 propertyDeedHash;
        bytes32 spvFormationDocHash;
    }

    constructor(InitParams memory p) ERC20(p.name, p.symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(SPONSOR_ROLE, p.sponsor);
        _grantRole(PROPERTY_MANAGER_ROLE, p.propertyManager);
        currency = IERC20(p.currency);
        eligibilityRegistry = IEligibilityCheck(p.eligibility);
        _requiredClaims = p.requiredClaims;
        initialValuationCurrency = p.initialValuationCurrency;
        propertyAddressHash = p.propertyAddressHash;
        propertyDeedHash = p.propertyDeedHash;
        spvFormationDocHash = p.spvFormationDocHash;
    }

    function mint(address to, uint256 shares) external onlyRole(SPONSOR_ROLE) {
        if (soldFlag) revert AlreadySold();
        _mint(to, shares);
    }

    // ---- Transfer eligibility + accrual ----

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

    // ---- Rental distribution ----

    /// @notice Property manager deposits net rental income for the period.
    ///         Frequency is operational — daily for RealT, monthly for larger
    ///         commercial properties.
    function depositRental(uint256 amount) external nonReentrant onlyRole(PROPERTY_MANAGER_ROLE) {
        if (soldFlag) revert AlreadySold();
        if (amount == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), amount);
        uint256 supply = totalSupply();
        if (supply > 0) {
            accCurrencyPerShare += (amount * PRECISION) / supply;
        }
        totalDistributed += amount;
        emit RentalDeposited(msg.sender, amount, accCurrencyPerShare);
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

    // ---- Sale of property ----

    /// @notice Sponsor deposits sale proceeds after physical sale closes. Sets
    ///         a per-share redemption rate; holders then call redeemSaleShare
    ///         to burn tokens and receive their pro-rata proceeds.
    function recordSale(uint256 saleProceeds) external nonReentrant onlyRole(SPONSOR_ROLE) {
        if (soldFlag) revert AlreadySold();
        if (saleProceeds == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), saleProceeds);
        uint256 supply = totalSupply();
        require(supply > 0, "no shares outstanding");
        salePoolPerShare = (saleProceeds * PRECISION) / supply;
        soldFlag = true;
        emit PropertySold(saleProceeds, supply, salePoolPerShare);
    }

    function redeemSaleShare() external nonReentrant {
        if (!soldFlag) revert NotYetSold();
        if (redeemedFromSale[msg.sender]) revert AlreadyRedeemed();
        uint256 bal = balanceOf(msg.sender);
        if (bal == 0) revert ZeroAmount();
        // Pay out any pending rental claims first.
        _accrue(msg.sender);
        uint256 rentDue = pendingReward[msg.sender];
        pendingReward[msg.sender] = 0;

        uint256 saleShare = (bal * salePoolPerShare) / PRECISION;
        redeemedFromSale[msg.sender] = true;
        _burn(msg.sender, bal);

        uint256 total = rentDue + saleShare;
        currency.safeTransfer(msg.sender, total);
        emit RedeemedFromSale(msg.sender, bal, total);
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
}
