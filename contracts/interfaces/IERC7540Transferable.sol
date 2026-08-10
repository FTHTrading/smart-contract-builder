// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-8161 — Transferable Tokenized Vault Requests
/// @notice Extension of ERC-7540 that allows a controller to transfer the
///         entire pending balance of a deposit or redeem request to a new
///         controller. Deposit and redeem transferability are independent
///         interfaces; a vault may implement either or both.
///
///         Spec: https://eips.ethereum.org/EIPS/eip-8161
///         Authors: Cain O'Sullivan, Jeroen Offerijns (Centrifuge)
///         Standard: ERC-8161 (Feb 2025)
///
///         Interface IDs (ERC-165):
///           - IERC7540DepositTransferable: 0x53b3bb0a
///           - IERC7540RedeemTransferable : 0x7846f5bd

/// @notice Pending deposit request transferability.
interface IERC7540DepositTransferable {
    /// @dev Emitted when a pending deposit request is transferred.
    ///      `sender` is msg.sender (may equal `from` or be an approved operator).
    event TransferDepositRequest(
        uint256 indexed requestId,
        address indexed from,
        address indexed to,
        address sender
    );

    /// @notice Transfers the entire pending deposit request balance from
    ///         `oldController` to `newController` for `requestId`. Claimable
    ///         balances MUST NOT be affected. msg.sender MUST be
    ///         `oldController` or an operator approved by `oldController`.
    ///         MUST emit `TransferDepositRequest`.
    function transferDepositRequest(
        uint256 requestId,
        address oldController,
        address newController
    ) external;
}

/// @notice Pending redeem request transferability.
interface IERC7540RedeemTransferable {
    /// @dev Emitted when a pending redeem request is transferred.
    ///      `sender` is msg.sender (may equal `from` or be an approved operator).
    event TransferRedeemRequest(
        uint256 indexed requestId,
        address indexed from,
        address indexed to,
        address sender
    );

    /// @notice Transfers the entire pending redeem request balance from
    ///         `oldController` to `newController` for `requestId`. Claimable
    ///         balances MUST NOT be affected. msg.sender MUST be
    ///         `oldController` or an operator approved by `oldController`.
    ///         MUST emit `TransferRedeemRequest`.
    function transferRedeemRequest(
        uint256 requestId,
        address oldController,
        address newController
    ) external;
}
