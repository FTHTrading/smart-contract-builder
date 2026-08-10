// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { ERC7540Transferable } from "../../mixins/ERC7540Transferable.sol";

/// @title AsyncVault7540
/// @notice Canonical ERC-7540 async request-based vault, extended with
///         ERC-8161 transferable pending requests.
///
///         Pattern: subscribers call `requestDeposit(assets, controller, owner)`
///         which pulls currency and enters a pending state. The fund admin
///         later calls `fulfillDeposit(controller, sharesAssigned)` which
///         moves the pending balance into a claimable balance at a specific
///         NAV. The controller then calls `deposit(assets, receiver, controller)`
///         to mint the shares. Redemptions follow the mirrored path.
///
///         Compliance is enforced by an external eligibility registry (the
///         library's PermissionedToken IdentityRegistry + ClaimTopicsRegistry
///         pair, or an equivalent ACE credential-check module).
///
///         ERC-165 support:
///           - IERC7540DepositTransferable: 0x53b3bb0a
///           - IERC7540RedeemTransferable : 0x7846f5bd
///           - Standard AccessControl / ERC-165
///
///         This contract is a REFERENCE. Production deployments should be
///         externally audited, wire the eligibility check to a real registry,
///         and integrate a real NAV oracle in place of the admin fulfillment
///         helpers exposed here.
contract AsyncVault7540 is ERC20, AccessControl, Pausable, ERC7540Transferable {
    using SafeERC20 for IERC20;

    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// Fixed requestId for this vault. Per ERC-7540, a vault MAY use a
    /// single canonical requestId (typical for simple funds) or per-cycle IDs.
    /// This reference implementation uses the canonical single-ID pattern.
    uint256 public constant REQUEST_ID = 0;

    IERC20 public immutable currency;
    IEligibilityCheck public immutable eligibilityRegistry;

    /// Claim topic IDs required to receive shares. Typical: [1 = KYC, 2 = accredited].
    uint256[] private _requiredClaims;

    /// ---- ERC-7540 pending / claimable accounting ----

    /// pending deposit assets awaiting fulfillment, per controller
    mapping(uint256 => mapping(address => uint256)) internal _pendingDeposits;
    /// claimable shares (post-fulfillment, pre-mint), per controller
    mapping(uint256 => mapping(address => uint256)) internal _claimableDepositShares;

    /// pending redeem shares awaiting fulfillment, per controller
    mapping(uint256 => mapping(address => uint256)) internal _pendingRedeems;
    /// claimable assets (post-fulfillment, pre-withdrawal), per controller
    mapping(uint256 => mapping(address => uint256)) internal _claimableRedeemAssets;

    /// ERC-7540 operator relation.
    mapping(address => mapping(address => bool)) internal _operators;

    /// Optional: fee applied on pending-request transfers, in basis points.
    /// Skimmed by the vault treasury. Default 0.
    uint256 public transferFeeBps;
    address public treasury;
    uint256 public constant BPS_DENOM = 10_000;

    /// ---- events ----

    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    event DepositRequested(uint256 indexed requestId, address indexed controller, address indexed owner, uint256 assets);
    event DepositFulfilled(uint256 indexed requestId, address indexed controller, uint256 assetsIn, uint256 sharesOut);
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    event RedeemRequested(uint256 indexed requestId, address indexed controller, address indexed owner, uint256 shares);
    event RedeemFulfilled(uint256 indexed requestId, address indexed controller, uint256 sharesIn, uint256 assetsOut);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    event TransferFeeUpdated(uint256 bps);
    event TreasuryUpdated(address treasury);
    event RequiredClaimsUpdated(uint256[] claims);

    error ReceiverNotEligible(address receiver);
    error NothingClaimable(address controller);
    error NotAuthorizedForOwner(address caller, address owner);
    error FeeTooHigh(uint256 bps);

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address currency_,
        address eligibility_,
        address treasury_,
        uint256[] memory requiredClaims_
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FULFILLER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        currency = IERC20(currency_);
        eligibilityRegistry = IEligibilityCheck(eligibility_);
        treasury = treasury_;
        _requiredClaims = requiredClaims_;
    }

    // ---- admin ----

    function setRequiredClaims(uint256[] calldata claims) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete _requiredClaims;
        for (uint256 i = 0; i < claims.length; i++) _requiredClaims.push(claims[i]);
        emit RequiredClaimsUpdated(claims);
    }
    function requiredClaims() external view returns (uint256[] memory) { return _requiredClaims; }

    function setTransferFeeBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > 100) revert FeeTooHigh(bps); // hard cap at 1%
        transferFeeBps = bps;
        emit TransferFeeUpdated(bps);
    }
    function setTreasury(address t) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = t;
        emit TreasuryUpdated(t);
    }
    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ---- transfer eligibility ----

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        if (to != address(0) && !eligibilityRegistry.eligibleFor(to, _requiredClaims)) {
            revert ReceiverNotEligible(to);
        }
        super._update(from, to, value);
    }

    // ==== ERC-7540 operator relation ====

    function setOperator(address operator, bool approved) external returns (bool) {
        _operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function isOperator(address controller, address operator)
        public
        view
        override
        returns (bool)
    {
        return _operators[controller][operator];
    }

    // ==== ERC-7540 deposit flow ====

    function requestDeposit(uint256 assets, address controller, address owner)
        external
        whenNotPaused
        returns (uint256 requestId)
    {
        if (msg.sender != owner && !isOperator(owner, msg.sender)) {
            revert NotAuthorizedForOwner(msg.sender, owner);
        }
        currency.safeTransferFrom(owner, address(this), assets);
        _pendingDeposits[REQUEST_ID][controller] += assets;
        emit DepositRequested(REQUEST_ID, controller, owner, assets);
        return REQUEST_ID;
    }

    function pendingDepositRequest(uint256 requestId, address controller)
        public
        view
        override
        returns (uint256)
    {
        return _pendingDeposits[requestId][controller];
    }

    function claimableDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256)
    {
        return _claimableDepositShares[requestId][controller];
    }

    /// @notice Fund admin call: moves `assets` from pending into claimable
    ///         shares at the specified NAV (shares assigned).
    function fulfillDeposit(address controller, uint256 assets, uint256 sharesOut)
        external
        onlyRole(FULFILLER_ROLE)
    {
        uint256 pending = _pendingDeposits[REQUEST_ID][controller];
        require(pending >= assets, "AsyncVault7540: exceeds pending");
        _pendingDeposits[REQUEST_ID][controller] = pending - assets;
        _claimableDepositShares[REQUEST_ID][controller] += sharesOut;
        emit DepositFulfilled(REQUEST_ID, controller, assets, sharesOut);
    }

    function deposit(uint256 /* assets */, address receiver, address controller)
        external
        returns (uint256 shares)
    {
        if (msg.sender != controller && !isOperator(controller, msg.sender)) {
            revert NotAuthorizedForOwner(msg.sender, controller);
        }
        shares = _claimableDepositShares[REQUEST_ID][controller];
        if (shares == 0) revert NothingClaimable(controller);
        _claimableDepositShares[REQUEST_ID][controller] = 0;
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, shares, shares);
    }

    // ==== ERC-7540 redeem flow ====

    function requestRedeem(uint256 shares, address controller, address owner)
        external
        whenNotPaused
        returns (uint256 requestId)
    {
        if (msg.sender != owner && !isOperator(owner, msg.sender)) {
            revert NotAuthorizedForOwner(msg.sender, owner);
        }
        _burn(owner, shares);
        _pendingRedeems[REQUEST_ID][controller] += shares;
        emit RedeemRequested(REQUEST_ID, controller, owner, shares);
        return REQUEST_ID;
    }

    function pendingRedeemRequest(uint256 requestId, address controller)
        public
        view
        override
        returns (uint256)
    {
        return _pendingRedeems[requestId][controller];
    }

    function claimableRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256)
    {
        return _claimableRedeemAssets[requestId][controller];
    }

    /// @notice Fund admin call: moves `shares` from pending into claimable
    ///         assets at the specified NAV (assets owed).
    function fulfillRedeem(address controller, uint256 shares, uint256 assetsOut)
        external
        onlyRole(FULFILLER_ROLE)
    {
        uint256 pending = _pendingRedeems[REQUEST_ID][controller];
        require(pending >= shares, "AsyncVault7540: exceeds pending");
        _pendingRedeems[REQUEST_ID][controller] = pending - shares;
        _claimableRedeemAssets[REQUEST_ID][controller] += assetsOut;
        emit RedeemFulfilled(REQUEST_ID, controller, shares, assetsOut);
    }

    function withdraw(uint256 /* assets */, address receiver, address controller)
        external
        returns (uint256 assets)
    {
        if (msg.sender != controller && !isOperator(controller, msg.sender)) {
            revert NotAuthorizedForOwner(msg.sender, controller);
        }
        assets = _claimableRedeemAssets[REQUEST_ID][controller];
        if (assets == 0) revert NothingClaimable(controller);
        _claimableRedeemAssets[REQUEST_ID][controller] = 0;
        currency.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, controller, assets, assets);
    }

    // ==== ERC-8161 mixin wiring ====

    function _debitPendingDeposit(uint256 requestId, address controller, uint256 amount)
        internal
        override
    {
        _pendingDeposits[requestId][controller] -= amount;
    }
    function _creditPendingDeposit(uint256 requestId, address controller, uint256 amount)
        internal
        override
    {
        _pendingDeposits[requestId][controller] += amount;
    }
    function _debitPendingRedeem(uint256 requestId, address controller, uint256 amount)
        internal
        override
    {
        _pendingRedeems[requestId][controller] -= amount;
    }
    function _creditPendingRedeem(uint256 requestId, address controller, uint256 amount)
        internal
        override
    {
        _pendingRedeems[requestId][controller] += amount;
    }

    /// @dev Fee-on-transfer hook — skims `transferFeeBps` off the transferred
    ///      pending balance and re-credits it to the treasury under the
    ///      SAME requestId (so treasury also holds a pending balance that
    ///      settles at the same NAV strike).
    function _beforeTransferDepositRequest(
        uint256 requestId,
        address /* oldController */,
        address /* newController */,
        uint256 amount
    ) internal override returns (uint256 amountAfterFee) {
        if (transferFeeBps == 0 || treasury == address(0)) return amount;
        uint256 fee = (amount * transferFeeBps) / BPS_DENOM;
        if (fee > 0) _pendingDeposits[requestId][treasury] += fee;
        return amount - fee;
    }

    function _beforeTransferRedeemRequest(
        uint256 requestId,
        address /* oldController */,
        address /* newController */,
        uint256 amount
    ) internal override returns (uint256 amountAfterFee) {
        if (transferFeeBps == 0 || treasury == address(0)) return amount;
        uint256 fee = (amount * transferFeeBps) / BPS_DENOM;
        if (fee > 0) _pendingRedeems[requestId][treasury] += fee;
        return amount - fee;
    }

    // ==== ERC-165 ====

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return interfaceId == IID_DEPOSIT_TRANSFERABLE
            || interfaceId == IID_REDEEM_TRANSFERABLE
            || super.supportsInterface(interfaceId);
    }
}

/// Minimal interface for the transfer eligibility check. Same signature as
/// TokenizedTreasury and other permissioned contracts in the library, so a
/// single PermissionedToken IdentityRegistry + ClaimTopicsRegistry pair can
/// serve every vault.
interface IEligibilityCheck {
    function eligibleFor(address holder, uint256[] calldata requiredClaims) external view returns (bool);
}
