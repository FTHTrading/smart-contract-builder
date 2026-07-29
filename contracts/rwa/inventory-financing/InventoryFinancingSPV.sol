// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title InventoryFinancingSPV
/// @notice Single-asset asset-backed loan against a physical inventory
///         collateral pile (equipment, commodities, vehicles). Reference use
///         case: a business with $2M of EV chargers in a warehouse who needs
///         working capital and posts the inventory as collateral for a
///         senior/junior tranche loan funded on-chain.
///
///         Not a pool. One SPV, one loan, one collateral pile, one UCC-1 lien.
///         For a pool of ongoing loans, use PoolDelegatePool (Maple-shape) or
///         BridgeLoanTranchePool (Centrifuge-shape) instead.
///
///         Structure (matches Centrifuge single-issue pattern):
///           1. Borrower deploys the SPV, sets loan amount + rate + tranches
///           2. Borrower posts junior tranche capital first (5-25% typical)
///           3. Whitelisted senior lenders deposit currency up to senior target
///           4. Once fully funded, principal transferred to borrower
///           5. Borrower makes periodic amortized repayments
///           6. Waterfall: senior interest → senior principal → junior residual
///           7. On default: junior consumed first, then senior takes loss
///
///         The UCC-1 lien reference is stored on-chain for the audit trail.
///         Physical enforcement remains in the traditional courts of the
///         collateral jurisdiction — this contract records what happened
///         cryptographically; it cannot foreclose on a warehouse.
contract InventoryFinancingSPV is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BORROWER_ROLE = keccak256("BORROWER_ROLE");
    bytes32 public constant SENIOR_LENDER_ROLE = keccak256("SENIOR_LENDER_ROLE");
    bytes32 public constant LEGAL_AGENT_ROLE = keccak256("LEGAL_AGENT_ROLE");

    /// Basis points denominator. 10_000 = 100%.
    uint256 public constant BPS_DENOM = 10_000;

    IERC20 public immutable currency;

    /// Total loan amount = seniorTarget + junior capital posted.
    uint256 public immutable seniorTarget;
    /// Junior tranche size, in bps of total loan (e.g. 2_000 = 20% junior).
    uint256 public immutable juniorBps;
    /// Annualized interest rate on the senior tranche, in bps.
    uint256 public immutable seniorRateBps;
    /// Loan term in seconds (e.g. 365 days).
    uint256 public immutable termSec;

    // ---- On-chain audit trail for the OFF-CHAIN legal instruments ----
    /// Sponsor-supplied description of the pledged collateral pile.
    string public collateralDescription;
    /// Physical location of the collateral (state + city + facility name).
    string public collateralLocation;
    /// Keccak256 hash of the executed UCC-1 filing document. The on-chain
    /// hash proves the document existed at loan origination; the physical
    /// filing with the Secretary of State's UCC office is the operative
    /// legal instrument.
    bytes32 public uccLienHash;
    /// State where the UCC-1 was filed (e.g. "TN" for Tennessee).
    string public uccFilingState;
    /// UCC filing number after successful lodgment.
    string public uccFilingNumber;

    // ---- Loan lifecycle ----
    enum Phase { Setup, Funding, Active, Repaid, Defaulted }
    Phase public phase;
    uint256 public originatedAt;
    uint256 public juniorPosted;
    uint256 public seniorRaised;
    uint256 public totalRepaid;
    uint256 public totalInterestPaid;

    /// Cumulative amount senior lenders are entitled to (grows as repayments come in).
    uint256 public seniorEntitlementCumulative;
    /// Cumulative amount junior tranche holder(s) are entitled to.
    uint256 public juniorEntitlementCumulative;

    /// Per-senior-lender contributions and claims.
    mapping(address => uint256) public seniorContribution;
    mapping(address => uint256) public seniorClaimed;
    mapping(address => uint256) public juniorClaimed;
    address public juniorHolder;

    event CollateralRecorded(string description, string location, bytes32 uccLienHash, string uccFilingState);
    event UCCFilingConfirmed(string filingNumber);
    event JuniorCapitalPosted(address indexed holder, uint256 amount);
    event SeniorFunded(address indexed lender, uint256 amount, uint256 totalRaised);
    event LoanOriginated(uint256 principal, uint256 originatedAt, uint256 maturityAt);
    event Repayment(uint256 amount, uint256 toSeniorInterest, uint256 toSeniorPrincipal, uint256 toJunior);
    event SeniorClaimed(address indexed lender, uint256 amount);
    event JuniorClaimed(address indexed holder, uint256 amount);
    event DefaultDeclared(uint256 outstandingPrincipal, string reason);

    error WrongPhase(Phase expected, Phase actual);
    error JuniorAmountWrong(uint256 required, uint256 got);
    error SeniorTargetExceeded(uint256 requested, uint256 remaining);
    error NotWhitelisted(address lender);
    error NoContribution(address account);
    error ZeroAmount();
    error UCCNotRecorded();

    struct InitParams {
        address admin;
        address borrower;
        address legalAgent;
        address currency;
        uint256 seniorTarget;
        uint256 juniorBps;
        uint256 seniorRateBps;
        uint256 termSec;
    }

    constructor(InitParams memory p) {
        require(p.juniorBps > 0 && p.juniorBps <= BPS_DENOM, "juniorBps 0-100%");
        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(BORROWER_ROLE, p.borrower);
        _grantRole(LEGAL_AGENT_ROLE, p.legalAgent);
        _grantRole(LEGAL_AGENT_ROLE, p.admin);
        currency = IERC20(p.currency);
        seniorTarget = p.seniorTarget;
        juniorBps = p.juniorBps;
        seniorRateBps = p.seniorRateBps;
        termSec = p.termSec;
        phase = Phase.Setup;
    }

    // ============================================================
    // Setup phase: record collateral + UCC-1 filing
    // ============================================================

    function recordCollateral(
        string calldata description,
        string calldata location,
        bytes32 uccLienHash_,
        string calldata uccFilingState_
    ) external onlyRole(LEGAL_AGENT_ROLE) {
        if (phase != Phase.Setup) revert WrongPhase(Phase.Setup, phase);
        collateralDescription = description;
        collateralLocation = location;
        uccLienHash = uccLienHash_;
        uccFilingState = uccFilingState_;
        emit CollateralRecorded(description, location, uccLienHash_, uccFilingState_);
    }

    /// @notice Legal agent records the UCC-1 filing number after successful
    ///         lodgment with the Secretary of State. Transitions to Funding phase.
    function confirmUCCFiling(string calldata filingNumber) external onlyRole(LEGAL_AGENT_ROLE) {
        if (phase != Phase.Setup) revert WrongPhase(Phase.Setup, phase);
        if (uccLienHash == bytes32(0)) revert UCCNotRecorded();
        uccFilingNumber = filingNumber;
        phase = Phase.Funding;
        emit UCCFilingConfirmed(filingNumber);
    }

    // ============================================================
    // Funding phase: borrower posts junior, senior lenders subscribe
    // ============================================================

    function whitelistSeniorLender(address lender) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SENIOR_LENDER_ROLE, lender);
    }
    function removeSeniorLender(address lender) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SENIOR_LENDER_ROLE, lender);
    }

    /// @notice Borrower posts the junior tranche capital first. Amount is
    ///         computed from seniorTarget and juniorBps (junior/(junior+senior)).
    ///         Must be posted before senior lenders can fund.
    function postJuniorCapital(uint256 amount) external onlyRole(BORROWER_ROLE) {
        if (phase != Phase.Funding) revert WrongPhase(Phase.Funding, phase);
        uint256 requiredJunior = (seniorTarget * juniorBps) / (BPS_DENOM - juniorBps);
        if (amount != requiredJunior) revert JuniorAmountWrong(requiredJunior, amount);
        currency.safeTransferFrom(msg.sender, address(this), amount);
        juniorPosted = amount;
        juniorHolder = msg.sender;
        emit JuniorCapitalPosted(msg.sender, amount);
    }

    /// @notice Whitelisted senior lender funds their contribution. When
    ///         seniorRaised hits seniorTarget, loan auto-originates.
    function fundSenior(uint256 amount) external nonReentrant {
        if (phase != Phase.Funding) revert WrongPhase(Phase.Funding, phase);
        if (juniorPosted == 0) revert WrongPhase(Phase.Funding, phase);
        if (!hasRole(SENIOR_LENDER_ROLE, msg.sender)) revert NotWhitelisted(msg.sender);
        uint256 remaining = seniorTarget - seniorRaised;
        if (amount > remaining) revert SeniorTargetExceeded(amount, remaining);
        if (amount == 0) revert ZeroAmount();

        currency.safeTransferFrom(msg.sender, address(this), amount);
        seniorContribution[msg.sender] += amount;
        seniorRaised += amount;
        emit SeniorFunded(msg.sender, amount, seniorRaised);

        if (seniorRaised == seniorTarget) _originate();
    }

    function _originate() internal {
        // Transfer full principal to borrower.
        uint256 principal = seniorRaised + juniorPosted;
        phase = Phase.Active;
        originatedAt = block.timestamp;
        // The borrower already holds BORROWER_ROLE; find them and transfer.
        // Since AccessControl doesn't enumerate role members without
        // AccessControlEnumerable, we track the borrower explicitly.
        // For simplicity we transfer to the LAST address that called
        // postJuniorCapital (juniorHolder — usually the borrower).
        currency.safeTransfer(juniorHolder, principal);
        emit LoanOriginated(principal, block.timestamp, block.timestamp + termSec);
    }

    // ============================================================
    // Active phase: repayments + waterfall
    // ============================================================

    /// @notice Borrower makes a repayment. Waterfall applied:
    ///          1. Accrued senior interest first
    ///          2. Senior principal reduction
    ///          3. Anything left → junior tranche entitlement
    ///
    ///         Simple-interest against actual holding period.
    function repay(uint256 amount) external nonReentrant onlyRole(BORROWER_ROLE) {
        if (phase != Phase.Active) revert WrongPhase(Phase.Active, phase);
        if (amount == 0) revert ZeroAmount();
        currency.safeTransferFrom(msg.sender, address(this), amount);
        totalRepaid += amount;

        // Compute accrued senior interest since origination, net of previously paid.
        uint256 elapsed = block.timestamp - originatedAt;
        uint256 accrued = (seniorRaised * seniorRateBps * elapsed) / (BPS_DENOM * 365 days);
        uint256 owedInterest = accrued > totalInterestPaid ? accrued - totalInterestPaid : 0;

        uint256 toInterest = amount > owedInterest ? owedInterest : amount;
        uint256 remaining = amount - toInterest;
        totalInterestPaid += toInterest;

        // Senior principal reduction from remaining
        uint256 seniorOutstanding = seniorRaised > (seniorEntitlementCumulative - totalInterestPaid)
            ? seniorRaised - (seniorEntitlementCumulative > totalInterestPaid ? seniorEntitlementCumulative - totalInterestPaid : 0)
            : 0;
        uint256 toSeniorPrincipal = remaining > seniorOutstanding ? seniorOutstanding : remaining;
        remaining -= toSeniorPrincipal;

        seniorEntitlementCumulative += toInterest + toSeniorPrincipal;
        juniorEntitlementCumulative += remaining;

        emit Repayment(amount, toInterest, toSeniorPrincipal, remaining);

        // Auto-mark repaid if senior is fully satisfied AND borrower has
        // returned junior capital + residual (approx: totalRepaid >= principal + accrued).
        if (seniorEntitlementCumulative >= seniorRaised && juniorEntitlementCumulative >= juniorPosted) {
            phase = Phase.Repaid;
        }
    }

    function claimSenior() external nonReentrant {
        uint256 contribution = seniorContribution[msg.sender];
        if (contribution == 0) revert NoContribution(msg.sender);
        uint256 entitled = (seniorEntitlementCumulative * contribution) / seniorRaised;
        uint256 due = entitled > seniorClaimed[msg.sender] ? entitled - seniorClaimed[msg.sender] : 0;
        if (due == 0) revert ZeroAmount();
        seniorClaimed[msg.sender] += due;
        currency.safeTransfer(msg.sender, due);
        emit SeniorClaimed(msg.sender, due);
    }

    function claimJunior() external nonReentrant {
        if (msg.sender != juniorHolder) revert NoContribution(msg.sender);
        uint256 due = juniorEntitlementCumulative > juniorClaimed[msg.sender]
            ? juniorEntitlementCumulative - juniorClaimed[msg.sender]
            : 0;
        if (due == 0) revert ZeroAmount();
        juniorClaimed[msg.sender] += due;
        currency.safeTransfer(msg.sender, due);
        emit JuniorClaimed(msg.sender, due);
    }

    // ============================================================
    // Default: legal agent declares; on-chain amount marks state,
    // enforcement is off-chain via the UCC-1 filed with the state.
    // ============================================================

    function declareDefault(string calldata reason) external onlyRole(LEGAL_AGENT_ROLE) {
        if (phase != Phase.Active) revert WrongPhase(Phase.Active, phase);
        phase = Phase.Defaulted;
        uint256 outstandingPrincipal = seniorRaised > seniorEntitlementCumulative
            ? seniorRaised - seniorEntitlementCumulative
            : 0;
        emit DefaultDeclared(outstandingPrincipal, reason);
    }

    // ============================================================
    // Views
    // ============================================================

    function requiredJuniorAmount() external view returns (uint256) {
        return (seniorTarget * juniorBps) / (BPS_DENOM - juniorBps);
    }

    function totalPrincipal() external view returns (uint256) {
        return seniorRaised + juniorPosted;
    }
}
