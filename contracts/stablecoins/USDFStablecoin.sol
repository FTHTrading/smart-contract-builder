// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IProofOfReserveGuard {
    function isMintAllowed(uint256 mintAmount) external view returns (bool);
}

/**
 * @title USDFStablecoin
 * @notice Unykorn USDF Sovereign Stablecoin — RWA and Treasury backed.
 * @dev Features Proof-of-Reserve mint gating, compliance sanctions freeze, fee sweeps, and permit offline approvals.
 */
contract USDFStablecoin is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    address public proofOfReserveGuard;
    address public treasury;
    uint16 public feeBps; // Fee in basis points (100 = 1%)
    uint16 public constant MAX_FEE_BPS = 500; // 5% max fee cap

    mapping(address => bool) private _blacklisted;

    event ProofOfReserveGuardUpdated(address indexed oldGuard, address indexed newGuard);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeeBpsUpdated(uint16 oldFee, uint16 newFee);
    event AccountFrozen(address indexed account);
    event AccountUnfrozen(address indexed account);
    event ComplianceForcedTransfer(address indexed from, address indexed to, uint256 amount);

    error AccountIsBlacklisted(address account);
    error ProofOfReserveMintBlocked(uint256 amount);
    error InvalidTreasuryAddress();
    error FeeExceedsMaximum(uint16 feeBps, uint16 maxFeeBps);

    constructor(
        string memory name,
        string memory symbol,
        address defaultAdmin,
        address initialTreasury,
        address initialPoRGuard
    )
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        if (initialTreasury == address(0)) revert InvalidTreasuryAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultAdmin);
        _grantRole(COMPLIANCE_ROLE, defaultAdmin);

        treasury = initialTreasury;
        proofOfReserveGuard = initialPoRGuard;
    }

    // ==== MINT & BURN ====

    /**
     * @notice Mint new USDF tokens. Gated by Proof-of-Reserve circuit breaker if configured.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (_blacklisted[to]) revert AccountIsBlacklisted(to);

        if (proofOfReserveGuard != address(0)) {
            bool allowed = IProofOfReserveGuard(proofOfReserveGuard).isMintAllowed(amount);
            if (!allowed) revert ProofOfReserveMintBlocked(amount);
        }

        _mint(to, amount);
    }

    /**
     * @notice Pause token transfers in emergency situations.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ==== COMPLIANCE & SANCTIONS ====

    function freezeAccount(address account) external onlyRole(COMPLIANCE_ROLE) {
        _blacklisted[account] = true;
        emit AccountFrozen(account);
    }

    function unfreezeAccount(address account) external onlyRole(COMPLIANCE_ROLE) {
        _blacklisted[account] = false;
        emit AccountUnfrozen(account);
    }

    function isFrozen(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    /**
     * @notice Force transfer funds from a blacklisted account pursuant to legal order.
     */
    function complianceForceTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(COMPLIANCE_ROLE) {
        if (to == address(0)) revert InvalidTreasuryAddress();
        bool wasBlacklisted = _blacklisted[from];
        _blacklisted[from] = false;
        _transfer(from, to, amount);
        if (wasBlacklisted) {
            _blacklisted[from] = true;
        }
        emit ComplianceForcedTransfer(from, to, amount);
    }

    // ==== CONFIGURATION ====

    function setProofOfReserveGuard(address newGuard) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ProofOfReserveGuardUpdated(proofOfReserveGuard, newGuard);
        proofOfReserveGuard = newGuard;
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setFeeBps(uint16 newFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeeBps > MAX_FEE_BPS) revert FeeExceedsMaximum(newFeeBps, MAX_FEE_BPS);
        emit FeeBpsUpdated(feeBps, newFeeBps);
        feeBps = newFeeBps;
    }

    // ==== OVERRIDES ====

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        if (_blacklisted[from]) revert AccountIsBlacklisted(from);
        if (_blacklisted[to]) revert AccountIsBlacklisted(to);

        // Apply fee sweep if configured and not minting/burning
        if (feeBps > 0 && from != address(0) && to != address(0) && from != treasury && to != treasury) {
            uint256 fee = (value * feeBps) / 10000;
            if (fee > 0) {
                value -= fee;
                super._update(from, treasury, fee);
            }
        }

        super._update(from, to, value);
    }
}
