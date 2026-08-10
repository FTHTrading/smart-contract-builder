// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StellarAssetAdapter
 * @notice Bridge interface adapter connecting EVM smart contracts to Stellar SEP-0008 compliance assets.
 */
contract StellarAssetAdapter is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct StellarSettlement {
        bytes32 stellarTxHash;
        address evmBeneficiary;
        uint256 amount;
        string assetCode;
        string issuerPublicKey;
        bool confirmed;
    }

    mapping(bytes32 => StellarSettlement) public settlements;

    event StellarBridgeInitiated(address indexed sender, string destinationStellarAccount, uint256 amount, string assetCode);
    event StellarSettlementConfirmed(bytes32 indexed stellarTxHash, address indexed beneficiary, uint256 amount);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    function initiateStellarBridge(
        string calldata destinationStellarAccount,
        uint256 amount,
        string calldata assetCode
    ) external {
        emit StellarBridgeInitiated(msg.sender, destinationStellarAccount, amount, assetCode);
    }

    function confirmStellarSettlement(
        bytes32 stellarTxHash,
        address beneficiary,
        uint256 amount,
        string calldata assetCode,
        string calldata issuerPublicKey
    ) external onlyRole(OPERATOR_ROLE) {
        settlements[stellarTxHash] = StellarSettlement({
            stellarTxHash: stellarTxHash,
            evmBeneficiary: beneficiary,
            amount: amount,
            assetCode: assetCode,
            issuerPublicKey: issuerPublicKey,
            confirmed: true
        });

        emit StellarSettlementConfirmed(stellarTxHash, beneficiary, amount);
    }
}
