// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title CustodyAttestationRegistry
/// @notice Generic on-chain registry for qualified-custodian vault attestations.
///         Multi-custodian by design: BitGo Enterprise, Anchorage Digital Bank,
///         Fireblocks, Fidelity Digital Assets, Coinbase Custody, Standard
///         Custody & Trust — each registers a signer address; each posts
///         EIP-712 signed vault-balance attestations at their own cadence.
///
///         Downstream contracts (TokenizedTreasury's IReserveGuard slot,
///         GoldBackedToken's PoR consumer, any minting circuit-breaker) query
///         the latest attested reserves per vaultId and decide whether a mint
///         can proceed.
///
///         Attestation shape (EIP-712 typed data):
///           - vaultId    — opaque per-vault identifier (custodian assigns)
///           - custodian  — which registered custodian
///           - asset      — asset being attested (address(0) for USD fiat / T-bills)
///           - balance    — reserve balance at attestedAt (raw units — asset
///                          decimals or 1e2 for USD cents)
///           - attestedAt — block timestamp when signer produced the message
///           - nonce      — monotonic per-vault, prevents replay
///
///         Signature verification uses OpenZeppelin's SignatureChecker so both
///         EOA signers and ERC-1271 contract signers (Gnosis Safe, BitGo
///         multi-sig signer contracts) work identically.
contract CustodyAttestationRegistry is AccessControl, EIP712 {
    using SignatureChecker for address;
    using ECDSA for bytes32;

    bytes32 public constant CUSTODIAN_ADMIN_ROLE = keccak256("CUSTODIAN_ADMIN_ROLE");

    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "VaultAttestation(bytes32 vaultId,address custodian,address asset,uint256 balance,uint256 attestedAt,uint256 nonce)"
    );

    struct StoredAttestation {
        address custodian;
        address asset;
        uint256 balance;
        uint256 attestedAt;
        uint256 nonce;
    }

    /// custodian => authorized signer address (EOA or ERC-1271 contract)
    mapping(address => address) public custodianSigner;
    /// custodian => human-readable name (for off-chain UIs)
    mapping(address => string) public custodianName;
    /// vaultId => latest accepted attestation
    mapping(bytes32 => StoredAttestation) public latest;
    /// vaultId => next expected nonce (last accepted + 1)
    mapping(bytes32 => uint256) public nextNonce;
    /// vaultId => the custodian responsible for it (assigned at first attestation)
    mapping(bytes32 => address) public vaultCustodian;

    event CustodianRegistered(address indexed custodian, address signer, string name);
    event CustodianSignerRotated(address indexed custodian, address oldSigner, address newSigner);
    event CustodianRemoved(address indexed custodian);
    event AttestationAccepted(
        bytes32 indexed vaultId,
        address indexed custodian,
        address asset,
        uint256 balance,
        uint256 attestedAt,
        uint256 nonce
    );

    error CustodianNotRegistered(address custodian);
    error NonceOutOfOrder(uint256 expected, uint256 provided);
    error InvalidSignature();
    error VaultBoundToDifferentCustodian(bytes32 vaultId, address bound, address provided);
    error AttestationInFuture(uint256 attestedAt, uint256 blockTime);

    constructor(address admin) EIP712("CustodyAttestationRegistry", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CUSTODIAN_ADMIN_ROLE, admin);
    }

    // ---- Custodian lifecycle ----

    function registerCustodian(address custodian, address signer, string calldata name)
        external onlyRole(CUSTODIAN_ADMIN_ROLE)
    {
        custodianSigner[custodian] = signer;
        custodianName[custodian] = name;
        emit CustodianRegistered(custodian, signer, name);
    }

    function rotateSigner(address custodian, address newSigner)
        external onlyRole(CUSTODIAN_ADMIN_ROLE)
    {
        address old = custodianSigner[custodian];
        if (old == address(0)) revert CustodianNotRegistered(custodian);
        custodianSigner[custodian] = newSigner;
        emit CustodianSignerRotated(custodian, old, newSigner);
    }

    function removeCustodian(address custodian) external onlyRole(CUSTODIAN_ADMIN_ROLE) {
        delete custodianSigner[custodian];
        delete custodianName[custodian];
        emit CustodianRemoved(custodian);
    }

    // ---- Attestation intake ----

    /// @notice Anyone can submit a signed attestation. Signature must verify
    ///         against the registered signer for the named custodian. Nonce
    ///         must be exactly nextNonce[vaultId]. VaultId, once first
    ///         attested by a custodian, binds to that custodian permanently.
    function attest(
        bytes32 vaultId,
        address custodian,
        address asset,
        uint256 balance,
        uint256 attestedAt,
        uint256 nonce,
        bytes calldata signature
    ) external {
        address signer = custodianSigner[custodian];
        if (signer == address(0)) revert CustodianNotRegistered(custodian);
        if (attestedAt > block.timestamp) revert AttestationInFuture(attestedAt, block.timestamp);
        if (nonce != nextNonce[vaultId]) revert NonceOutOfOrder(nextNonce[vaultId], nonce);

        address bound = vaultCustodian[vaultId];
        if (bound == address(0)) {
            vaultCustodian[vaultId] = custodian;
        } else if (bound != custodian) {
            revert VaultBoundToDifferentCustodian(vaultId, bound, custodian);
        }

        bytes32 structHash = keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            vaultId,
            custodian,
            asset,
            balance,
            attestedAt,
            nonce
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!signer.isValidSignatureNow(digest, signature)) revert InvalidSignature();

        latest[vaultId] = StoredAttestation({
            custodian: custodian,
            asset: asset,
            balance: balance,
            attestedAt: attestedAt,
            nonce: nonce
        });
        nextNonce[vaultId] = nonce + 1;
        emit AttestationAccepted(vaultId, custodian, asset, balance, attestedAt, nonce);
    }

    // ---- Read helpers ----

    /// @notice Returns the latest attested balance for a vault, or zero if
    ///         never attested. Callers wanting freshness must additionally
    ///         check attestedAt against a staleness window.
    function attestedBalance(bytes32 vaultId) external view returns (uint256) {
        return latest[vaultId].balance;
    }

    function attestedAt(bytes32 vaultId) external view returns (uint256) {
        return latest[vaultId].attestedAt;
    }

    /// @notice Convenience: computes staleness for a vault attestation.
    ///         Returns 0 if never attested; otherwise seconds since attestation.
    function attestationAge(bytes32 vaultId) external view returns (uint256) {
        uint256 t = latest[vaultId].attestedAt;
        if (t == 0) return 0;
        return block.timestamp - t;
    }
}
