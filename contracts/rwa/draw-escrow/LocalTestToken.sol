// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title LocalTestToken
/// @notice Development-only ERC20 standing in for the settlement currency
///         (USDC on mainnet, USDF in the UnyKorn stack). 18 decimals to keep
///         local math legible; production uses 6-decimal USDC.
///         Only mintable by the deployer. Never intended for a real chain.
contract LocalTestToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Local Test Token", "LTT") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
