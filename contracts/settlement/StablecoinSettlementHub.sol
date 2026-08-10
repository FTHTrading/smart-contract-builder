// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StablecoinSettlementHub
 * @notice Atomic Multi-Stablecoin Settlement and Liquidity Router supporting swaps between USDC, USDT, RLUSD, USDF, USDG, PYUSD, BUIDL, and BENJI.
 */
contract StablecoinSettlementHub is AccessControl, ReentrancyGuard {
    bytes32 public constant SETTLEMENT_ADMIN_ROLE = keccak256("SETTLEMENT_ADMIN_ROLE");

    struct LiquidityPool {
        address tokenAddress;
        string symbol;
        uint256 reserveBalance;
        bool active;
    }

    // symbol => LiquidityPool
    mapping(string => LiquidityPool) public pools;
    string[] public supportedTokens;

    uint256 public constant BPS_DENOM = 10000;
    uint16 public feeBps = 10; // 10 bps (0.10%) settlement fee

    event SettlementExecuted(address indexed sender, string fromSymbol, string toSymbol, uint256 inputAmount, uint256 outputAmount);
    event LiquidityAdded(string symbol, uint256 amount);

    error UnsupportedToken(string symbol);
    error InsufficientLiquidity(string symbol, uint256 required, uint256 available);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTLEMENT_ADMIN_ROLE, admin);
    }

    function registerTokenPool(string calldata symbol, address tokenAddress) external onlyRole(SETTLEMENT_ADMIN_ROLE) {
        if (pools[symbol].tokenAddress == address(0)) {
            supportedTokens.push(symbol);
        }

        pools[symbol] = LiquidityPool({
            tokenAddress: tokenAddress,
            symbol: symbol,
            reserveBalance: 0,
            active: true
        });
    }

    /**
     * @notice Atomic settlement swap between two stablecoins or treasury tokens.
     */
    function swapStablecoins(
        string calldata fromSymbol,
        string calldata toSymbol,
        uint256 inputAmount
    ) external nonReentrant returns (uint256 outputAmount) {
        if (!pools[fromSymbol].active) revert UnsupportedToken(fromSymbol);
        if (!pools[toSymbol].active) revert UnsupportedToken(toSymbol);

        uint256 fee = (inputAmount * feeBps) / BPS_DENOM;
        outputAmount = inputAmount - fee;

        if (pools[toSymbol].reserveBalance < outputAmount) {
            revert InsufficientLiquidity(toSymbol, outputAmount, pools[toSymbol].reserveBalance);
        }

        pools[fromSymbol].reserveBalance += inputAmount;
        pools[toSymbol].reserveBalance -= outputAmount;

        if (pools[fromSymbol].tokenAddress != address(0)) {
            IERC20(pools[fromSymbol].tokenAddress).transferFrom(msg.sender, address(this), inputAmount);
        }

        if (pools[toSymbol].tokenAddress != address(0)) {
            IERC20(pools[toSymbol].tokenAddress).transfer(msg.sender, outputAmount);
        }

        emit SettlementExecuted(msg.sender, fromSymbol, toSymbol, inputAmount, outputAmount);
    }

    function addLiquidity(string calldata symbol, uint256 amount) external onlyRole(SETTLEMENT_ADMIN_ROLE) {
        pools[symbol].reserveBalance += amount;
        emit LiquidityAdded(symbol, amount);
    }
}
