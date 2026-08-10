// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title FundAdministration
 * @notice On-chain fund administration and lifecycle manager for Mutual Funds, Private Credit, REITs, Infrastructure, and Sports Funds.
 */
contract FundAdministration is AccessControl {
    bytes32 public constant FUND_ADMIN_ROLE = keccak256("FUND_ADMIN_ROLE");

    enum FundType {
        MutualFund,
        PrivateCredit,
        REIT,
        Infrastructure,
        SportsFund,
        TreasuryFund
    }

    struct Fund {
        bytes32 fundId;
        string name;
        string symbol;
        FundType fundType;
        address fundManager;
        address navOracleAddress;
        uint256 minInvestmentUSD;
        uint256 totalAUMUSD;
        bool openForSubscription;
        bool active;
    }

    mapping(bytes32 => Fund) public funds;
    bytes32[] public fundKeys;

    event FundRegistered(bytes32 indexed fundId, string name, FundType indexed fundType, address fundManager);
    event FundAUMUpdated(bytes32 indexed fundId, uint256 newAUMUSD);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FUND_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerFund(
        string calldata name,
        string calldata symbol,
        FundType fundType,
        address fundManager,
        address navOracleAddress,
        uint256 minInvestmentUSD
    ) external onlyRole(FUND_ADMIN_ROLE) returns (bytes32 fundId) {
        fundId = keccak256(abi.encodePacked(name, symbol, block.timestamp));

        funds[fundId] = Fund({
            fundId: fundId,
            name: name,
            symbol: symbol,
            fundType: fundType,
            fundManager: fundManager,
            navOracleAddress: navOracleAddress,
            minInvestmentUSD: minInvestmentUSD,
            totalAUMUSD: 0,
            openForSubscription: true,
            active: true
        });

        fundKeys.push(fundId);
        emit FundRegistered(fundId, name, fundType, fundManager);
    }

    function updateAUM(bytes32 fundId, uint256 newAUMUSD) external onlyRole(FUND_ADMIN_ROLE) {
        funds[fundId].totalAUMUSD = newAUMUSD;
        emit FundAUMUpdated(fundId, newAUMUSD);
    }

    function getFund(bytes32 fundId) external view returns (Fund memory) {
        return funds[fundId];
    }

    function _initializeDefaults() internal {
        bytes32 buidlId = keccak256("BLACKROCK_BUIDL_FUND");
        funds[buidlId] = Fund({
            fundId: buidlId,
            name: "BlackRock USD Institutional Digital Liquidity Fund",
            symbol: "BUIDL",
            fundType: FundType.TreasuryFund,
            fundManager: address(0x8881),
            navOracleAddress: address(0),
            minInvestmentUSD: 5_000_000 * 1e18,
            totalAUMUSD: 500_000_000 * 1e18,
            openForSubscription: true,
            active: true
        });
        fundKeys.push(buidlId);
    }
}
