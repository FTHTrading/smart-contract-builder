// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title XRPLHooksAdapter
 * @notice Bridge interface adapter connecting EVM smart contracts to XRPL native MPT (Multi-Purpose Tokens) & C Hooks.
 */
contract XRPLHooksAdapter is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct XRPLTokenRequest {
        bytes32 xrplTxHash;
        address evmRecipient;
        uint256 amount;
        string currencyCode;
        bytes32 issuerAccount;
        bool processed;
    }

    mapping(bytes32 => XRPLTokenRequest) public pendingRequests;

    event XRPLBridgeInitiated(address indexed sender, bytes32 indexed destinationXRPLAccount, uint256 amount, string currencyCode);
    event XRPLBridgeCompleted(bytes32 indexed xrplTxHash, address indexed evmRecipient, uint256 amount);

    error AlreadyProcessed(bytes32 xrplTxHash);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    /**
     * @notice Initiate a bridge request from EVM to XRPL Multi-Purpose Token (MPT).
     */
    function initiateXRPLBridge(
        bytes32 destinationXRPLAccount,
        uint256 amount,
        string calldata currencyCode
    ) external {
        emit XRPLBridgeInitiated(msg.sender, destinationXRPLAccount, amount, currencyCode);
    }

    /**
     * @notice Complete a bridge request verified by XRPL Hook attestation.
     */
    function completeXRPLBridge(
        bytes32 xrplTxHash,
        address evmRecipient,
        uint256 amount,
        string calldata currencyCode,
        bytes32 issuerAccount
    ) external onlyRole(OPERATOR_ROLE) {
        if (pendingRequests[xrplTxHash].processed) revert AlreadyProcessed(xrplTxHash);

        pendingRequests[xrplTxHash] = XRPLTokenRequest({
            xrplTxHash: xrplTxHash,
            evmRecipient: evmRecipient,
            amount: amount,
            currencyCode: currencyCode,
            issuerAccount: issuerAccount,
            processed: true
        });

        emit XRPLBridgeCompleted(xrplTxHash, evmRecipient, amount);
    }
}
