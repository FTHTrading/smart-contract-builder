// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Waiver types
/// @notice File-level types shared by DrawEscrow and any consumer verifying a
///         statutory-form lien waiver commitment. The on-chain waiverHash MUST be
///         the keccak256 of the executed waiver document in its jurisdictionally-
///         prescribed form. The contract evidences the waiver; it does not
///         constitute or replace the statutory form.
///
///         The attestor is an EOA (title-company employee's wallet) or any
///         ERC-1271 contract wallet — DrawEscrow uses OZ SignatureChecker so both
///         paths verify identically without a wrapping attestor contract.
enum WaiverKind {
    ConditionalProgress,
    UnconditionalProgress,
    ConditionalFinal,
    UnconditionalFinal
}

struct Waiver {
    bytes32 waiverHash;      // keccak256 of the off-chain statutory-form document bytes
    bytes32 projectId;       // deal / SPV identifier (immutable on the escrow)
    uint256 milestoneId;     // milestone this waiver covers
    uint256 drawNumber;      // sequential draw number FOR THIS MILESTONE — replay-guard field
    uint256 throughAmount;   // "through" dollar amount in the statutory form
    WaiverKind kind;
    address claimant;        // party granting the waiver (subcontractor / GC)
    uint256 issuedAt;        // unix seconds the paper was signed
}
