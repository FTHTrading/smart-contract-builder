// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

interface ICustodyAttestationRegistry {
    function attestedBalance(bytes32 vaultId) external view returns (uint256);
    function attestedAt(bytes32 vaultId) external view returns (uint256);
}

/// @title CustodyReserveGuard
/// @notice Implements the IReserveGuard interface consumed by TokenizedTreasury,
///         GoldBackedToken, and any other mint-gated RWA token. Reads the
///         latest attested custody balance for a configured vaultId from a
///         CustodyAttestationRegistry and refuses the mint if reserves would
///         drop below the required over-collateralization ratio, or if the
///         latest attestation is stale beyond a configured window.
///
///         Same circuit-breaker shape 21.co (ARK BTC ETF), Backed, Bedrock,
///         and Bancolombia use in production — but instead of a single
///         Chainlink PoR feed, this reads from a self-hosted, multi-custodian
///         registry. Compatible with the Chainlink PoR flow: point the
///         TokenizedTreasury at Chainlink for market-data-attested assets
///         (BTC, ETH, gold) and at this contract for direct-custody-attested
///         assets (T-bills, cash sitting in a qualified custodian).
contract CustodyReserveGuard is AccessControl {
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    uint256 public constant BPS_DENOM = 10_000;

    ICustodyAttestationRegistry public immutable registry;

    /// The vault this guard watches. Set at deploy; can be rotated by admin
    /// if the fund migrates custody providers.
    bytes32 public vaultId;

    /// Over-collateralization requirement in bps. e.g. 10_100 means reserves
    /// must be at least 101% of (currentSupply + mintAmount). 10_000 is
    /// 1-to-1 (strict full reserves, no over-collateral).
    uint256 public overCollateralBps;

    /// Max age (in seconds) for the latest attestation to be considered
    /// valid. Beyond this, mints are blocked regardless of attested balance.
    /// Typical: 86400 (1 day) for BUIDL / OUSG-shape treasuries where the
    /// custodian posts daily; 3600 for more real-time-attested assets.
    uint256 public maxStalenessSec;

    event VaultRotated(bytes32 oldVaultId, bytes32 newVaultId);
    event OverCollateralRotated(uint256 oldBps, uint256 newBps);
    event StalenessRotated(uint256 oldSec, uint256 newSec);

    error InsufficientReserves(uint256 reserves, uint256 required);
    error AttestationStale(uint256 age, uint256 max);
    error NoAttestation();

    constructor(
        address admin,
        ICustodyAttestationRegistry registry_,
        bytes32 vaultId_,
        uint256 overCollateralBps_,
        uint256 maxStalenessSec_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);
        registry = registry_;
        vaultId = vaultId_;
        overCollateralBps = overCollateralBps_;
        maxStalenessSec = maxStalenessSec_;
    }

    // ---- Admin ----

    function setVaultId(bytes32 newVaultId) external onlyRole(CONFIG_ADMIN_ROLE) {
        emit VaultRotated(vaultId, newVaultId);
        vaultId = newVaultId;
    }

    function setOverCollateralBps(uint256 newBps) external onlyRole(CONFIG_ADMIN_ROLE) {
        emit OverCollateralRotated(overCollateralBps, newBps);
        overCollateralBps = newBps;
    }

    function setMaxStalenessSec(uint256 newSec) external onlyRole(CONFIG_ADMIN_ROLE) {
        emit StalenessRotated(maxStalenessSec, newSec);
        maxStalenessSec = newSec;
    }

    // ---- IReserveGuard implementation ----

    /// @notice Called by the mint-gated RWA token before it mints. Reverts if
    ///         reserves would be insufficient for currentSupply + mintAmount
    ///         at the configured over-collateral ratio, or if the latest
    ///         attestation is stale.
    function requireCanMint(uint256 currentSupply, uint256 mintAmount) external view {
        uint256 attestedTime = registry.attestedAt(vaultId);
        if (attestedTime == 0) revert NoAttestation();
        uint256 age = block.timestamp - attestedTime;
        if (age > maxStalenessSec) revert AttestationStale(age, maxStalenessSec);

        uint256 required = ((currentSupply + mintAmount) * overCollateralBps) / BPS_DENOM;
        uint256 reserves = registry.attestedBalance(vaultId);
        if (reserves < required) revert InsufficientReserves(reserves, required);
    }
}
