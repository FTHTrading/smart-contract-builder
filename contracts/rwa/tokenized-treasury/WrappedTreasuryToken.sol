// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title WrappedTreasuryToken
/// @notice ERC-4626 composability wrapper for a permissioned tokenized treasury
///         token (BUIDL, BENJI, OUSG, USYC, USDY, TBILL, etc.). The base token
///         is transfer-restricted to KYC'd holders; this wrapper holds the base
///         tokens in custody and issues an unrestricted ERC-4626 share.
///
///         Reference shapes:
///           - sBUIDL / bIB01 / iUSD — wrapper tokens issued against permissioned
///             tokenized treasuries so they can be used as DeFi collateral
///           - wstETH pattern — exchange-rate wrapper, no rebasing, DeFi-friendly
///
///         Why ERC-4626 not rebasing:
///           - Every AMM, lending market, and vault protocol supports ERC-4626
///           - Rebasing tokens break rounding assumptions in most DeFi contracts
///           - Exchange-rate model means the wrapper's totalSupply is stable
///             while the underlying grows via base-token yield accrual
///
///         Prerequisites for deployment:
///           1. The base tokenized treasury MUST whitelist this wrapper contract
///              as an eligible holder (call IdentityRegistry.registerIdentity
///              for this contract's address with all required claim topics)
///           2. Withdrawals ONLY succeed to receivers who are ALSO whitelisted
///              on the base treasury — the underlying transfer to a non-eligible
///              recipient will revert at the base contract's _update hook
///
///         Yield accrual:
///           - If the base distributes yield via mint-to-holders (e.g. BUIDL's
///             daily dividend mints new shares to holders), this wrapper's
///             underlying balance grows automatically → exchange rate rises
///             → wrapper holders realize yield on withdrawal
///           - If the base distributes yield via a separate stablecoin claim
///             (e.g. USYC's coupon accrual), a poke() function can be added
///             later to relay to holders; not included in v1 to keep the
///             wrapper minimal and audit-friendly
contract WrappedTreasuryToken is ERC4626, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// keccak256 hash of the base treasury's ISIN / CUSIP / fund identifier for
    /// off-chain reconciliation. Not enforced on-chain; evidentiary anchor.
    bytes32 public immutable baseIdentifierHash;

    /// Flag: has emergency pause been triggered. If true, deposits blocked.
    bool public depositsPaused;

    event DepositsPaused(address indexed by);
    event DepositsResumed(address indexed by);

    error DepositsArePaused();

    constructor(
        IERC20 baseToken,
        string memory name_,
        string memory symbol_,
        address admin,
        bytes32 baseIdentifierHash_
    ) ERC4626(baseToken) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EMERGENCY_ROLE, admin);
        baseIdentifierHash = baseIdentifierHash_;
    }

    // ---- Deposit-pause emergency lever ----
    // Withdrawals are NEVER pauseable — holders must always be able to exit.
    // Only new inflows can be halted, and only for a genuine emergency (base
    // token compromised, unexpected reserve depletion, etc.).

    function pauseDeposits() external onlyRole(EMERGENCY_ROLE) {
        depositsPaused = true;
        emit DepositsPaused(msg.sender);
    }

    function resumeDeposits() external onlyRole(EMERGENCY_ROLE) {
        depositsPaused = false;
        emit DepositsResumed(msg.sender);
    }

    // ---- ERC-4626 deposit hooks ----
    // Override the internal deposit path to enforce the pause. All ERC-4626
    // entry points (deposit, mint) route through _deposit → we gate there.

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (depositsPaused) revert DepositsArePaused();
        super._deposit(caller, receiver, assets, shares);
    }

    // No _withdraw override — withdrawals stay open forever. The base treasury
    // will independently revert the underlying transfer if the receiver is not
    // KYC'd. That's the correct behavior: unwrap always succeeds on the
    // wrapper side; the base decides whether the recipient can hold shares.
}
