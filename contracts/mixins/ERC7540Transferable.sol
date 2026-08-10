// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC7540DepositTransferable,
    IERC7540RedeemTransferable
} from "../interfaces/IERC7540Transferable.sol";

/// @title ERC7540Transferable
/// @notice Abstract ERC-8161 mixin. Inherit alongside an ERC-7540 async vault
///         to add transferable pending deposit and/or redeem requests.
///
///         Wiring pattern for the inheriting vault:
///
///           1. Implement `pendingDepositRequest`, `pendingRedeemRequest`,
///              and `isOperator` against the vault's own storage.
///
///           2. Implement `_debitPendingDeposit`, `_creditPendingDeposit`,
///              `_debitPendingRedeem`, `_creditPendingRedeem` — these are
///              storage-level mutations that mirror what happens on
///              subscription / cancellation, but with no ERC-20 or currency
///              movement (only the pending accounting shifts between
///              controllers).
///
///           3. Optionally override `_beforeTransferDepositRequest` /
///              `_beforeTransferRedeemRequest` to charge a transfer fee or
///              enforce vault-specific rules (e.g. `newController` KYC
///              check). Default implementations are no-ops.
///
///           4. Return true from `supportsInterface` for one or both of the
///              constants exposed here as `IID_DEPOSIT_TRANSFERABLE` /
///              `IID_REDEEM_TRANSFERABLE`.
///
///         Security posture:
///           - Reverts on zero-address `newController`.
///           - Reverts if `msg.sender` is neither `oldController` nor an
///             approved operator.
///           - Reverts if pending balance is zero (prevents empty transfers
///             from polluting the event log).
///           - Transfers the FULL pending balance per spec — no partial
///             transfers. Callers that need partial semantics should cancel
///             and re-request.
///
/// @dev Spec: https://eips.ethereum.org/EIPS/eip-8161
abstract contract ERC7540Transferable is
    IERC7540DepositTransferable,
    IERC7540RedeemTransferable
{
    /// ERC-165 interface IDs.
    bytes4 public constant IID_DEPOSIT_TRANSFERABLE = 0x53b3bb0a;
    bytes4 public constant IID_REDEEM_TRANSFERABLE  = 0x7846f5bd;

    error ZeroController();
    error NotAuthorized(address caller, address controller);
    error NothingPending(uint256 requestId, address controller);

    // ---- vault must implement against its own storage ----

    /// @notice Return the current pending deposit request balance for
    ///         `controller` under `requestId`.
    function pendingDepositRequest(uint256 requestId, address controller)
        public
        view
        virtual
        returns (uint256);

    /// @notice Return the current pending redeem request balance for
    ///         `controller` under `requestId`.
    function pendingRedeemRequest(uint256 requestId, address controller)
        public
        view
        virtual
        returns (uint256);

    /// @notice ERC-7540 operator relation.
    function isOperator(address controller, address operator)
        public
        view
        virtual
        returns (bool);

    /// @dev Storage-level debit/credit hooks. Implementations MUST NOT
    ///      move any currency or shares — only the pending accounting.
    function _debitPendingDeposit(uint256 requestId, address controller, uint256 amount)
        internal
        virtual;

    function _creditPendingDeposit(uint256 requestId, address controller, uint256 amount)
        internal
        virtual;

    function _debitPendingRedeem(uint256 requestId, address controller, uint256 amount)
        internal
        virtual;

    function _creditPendingRedeem(uint256 requestId, address controller, uint256 amount)
        internal
        virtual;

    // ---- optional pre-transfer hooks (default no-op) ----

    /// @dev Override to charge a transfer fee or enforce receiver rules
    ///      (e.g. KYC check on `newController`). Returning `amountAfterFee`
    ///      allows a fee-on-transfer pattern. Default returns `amount`.
    function _beforeTransferDepositRequest(
        uint256 /* requestId */,
        address /* oldController */,
        address /* newController */,
        uint256 amount
    ) internal virtual returns (uint256 amountAfterFee) {
        return amount;
    }

    function _beforeTransferRedeemRequest(
        uint256 /* requestId */,
        address /* oldController */,
        address /* newController */,
        uint256 amount
    ) internal virtual returns (uint256 amountAfterFee) {
        return amount;
    }

    // ---- external transfer methods ----

    /// @inheritdoc IERC7540DepositTransferable
    function transferDepositRequest(
        uint256 requestId,
        address oldController,
        address newController
    ) external virtual override {
        if (newController == address(0)) revert ZeroController();
        if (msg.sender != oldController && !isOperator(oldController, msg.sender)) {
            revert NotAuthorized(msg.sender, oldController);
        }

        uint256 pending = pendingDepositRequest(requestId, oldController);
        if (pending == 0) revert NothingPending(requestId, oldController);

        uint256 credited = _beforeTransferDepositRequest(
            requestId, oldController, newController, pending
        );

        _debitPendingDeposit(requestId, oldController, pending);
        _creditPendingDeposit(requestId, newController, credited);

        emit TransferDepositRequest(requestId, oldController, newController, msg.sender);
    }

    /// @inheritdoc IERC7540RedeemTransferable
    function transferRedeemRequest(
        uint256 requestId,
        address oldController,
        address newController
    ) external virtual override {
        if (newController == address(0)) revert ZeroController();
        if (msg.sender != oldController && !isOperator(oldController, msg.sender)) {
            revert NotAuthorized(msg.sender, oldController);
        }

        uint256 pending = pendingRedeemRequest(requestId, oldController);
        if (pending == 0) revert NothingPending(requestId, oldController);

        uint256 credited = _beforeTransferRedeemRequest(
            requestId, oldController, newController, pending
        );

        _debitPendingRedeem(requestId, oldController, pending);
        _creditPendingRedeem(requestId, newController, credited);

        emit TransferRedeemRequest(requestId, oldController, newController, msg.sender);
    }
}
