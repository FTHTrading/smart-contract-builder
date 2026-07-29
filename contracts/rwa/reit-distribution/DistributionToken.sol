// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

interface IREITDistributor {
    function onBalanceChanged(address from, address to, uint256 amount) external;
}

/// @title DistributionToken
/// @notice ERC-20 unit token whose _update hook notifies its Distributor of
///         balance changes so the accumulator pattern can settle dividend
///         debt cleanly on transfer / mint / burn.
contract DistributionToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant HOOK_ADMIN_ROLE = keccak256("HOOK_ADMIN_ROLE");

    IREITDistributor public distributor;

    event DistributorSet(address indexed distributor);

    constructor(string memory name_, string memory symbol_, address admin)
        ERC20(name_, symbol_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(HOOK_ADMIN_ROLE, admin);
    }

    function setDistributor(address d) external onlyRole(HOOK_ADMIN_ROLE) {
        distributor = IREITDistributor(d);
        emit DistributorSet(d);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        // Settle dividend debt BEFORE the balance change actually happens so
        // the accumulator math uses pre-transfer balances.
        if (address(distributor) != address(0)) {
            distributor.onBalanceChanged(from, to, value);
        }
        super._update(from, to, value);
    }
}
