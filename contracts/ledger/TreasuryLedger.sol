// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title TreasuryLedger
 * @notice On-chain General Ledger for digital assets tracking Assets, Liabilities, Income, Fees, Reserves, Settlements, Counterparty Exposure, and AUM statements.
 */
contract TreasuryLedger is AccessControl {
    bytes32 public constant LEDGER_ADMIN_ROLE = keccak256("LEDGER_ADMIN_ROLE");
    bytes32 public constant ACCOUNTANT_ROLE   = keccak256("ACCOUNTANT_ROLE");

    enum EntryType {
        AssetDeposit,
        AssetWithdrawal,
        YieldIncome,
        ManagementFee,
        SettlementRouting,
        ReserveAdjustment
    }

    struct LedgerEntry {
        uint256 entryId;
        address entityAccount;
        string assetSymbol;
        EntryType entryType;
        uint256 amountUSD; // scaled 1e18
        uint256 timestamp;
        string counterparty;
        bytes32 referenceHash;
    }

    LedgerEntry[] public ledger;

    // entityAccount => assetSymbol => balanceUSD
    mapping(address => mapping(string => uint256)) public accountBalances;
    // entityAccount => totalAUMUSD
    mapping(address => uint256) public totalEntityAUM;

    event LedgerEntryPosted(uint256 indexed entryId, address indexed entityAccount, string assetSymbol, EntryType entryType, uint256 amountUSD);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LEDGER_ADMIN_ROLE, admin);
        _grantRole(ACCOUNTANT_ROLE, admin);
    }

    function postEntry(
        address entityAccount,
        string calldata assetSymbol,
        EntryType entryType,
        uint256 amountUSD,
        string calldata counterparty,
        bytes32 referenceHash
    ) external onlyRole(ACCOUNTANT_ROLE) returns (uint256 entryId) {
        entryId = ledger.length;

        ledger.push(LedgerEntry({
            entryId: entryId,
            entityAccount: entityAccount,
            assetSymbol: assetSymbol,
            entryType: entryType,
            amountUSD: amountUSD,
            timestamp: block.timestamp,
            counterparty: counterparty,
            referenceHash: referenceHash
        }));

        if (entryType == EntryType.AssetDeposit || entryType == EntryType.YieldIncome) {
            accountBalances[entityAccount][assetSymbol] += amountUSD;
            totalEntityAUM[entityAccount] += amountUSD;
        } else if (entryType == EntryType.AssetWithdrawal || entryType == EntryType.ManagementFee) {
            if (accountBalances[entityAccount][assetSymbol] >= amountUSD) {
                accountBalances[entityAccount][assetSymbol] -= amountUSD;
            }
            if (totalEntityAUM[entityAccount] >= amountUSD) {
                totalEntityAUM[entityAccount] -= amountUSD;
            }
        }

        emit LedgerEntryPosted(entryId, entityAccount, assetSymbol, entryType, amountUSD);
    }

    function getLedgerCount() external view returns (uint256) {
        return ledger.length;
    }

    function getEntityAUM(address entityAccount) external view returns (uint256) {
        return totalEntityAUM[entityAccount];
    }
}
