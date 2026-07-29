// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { Waiver, WaiverKind } from "./IWaiverAttestor.sol";
import { MilestoneRegistry } from "./MilestoneRegistry.sol";

/// @title DrawEscrow
/// @notice Milestone-indexed construction draw escrow. Releases funds to a payee only when
///         (a) an inspector-attested milestone completion is on record in MilestoneRegistry,
///         (b) a signed, hash-committed lien waiver artifact is presented for the same
///             milestone and throughAmount, and (c) retainage math holds.
///
///         The on-chain contract is EVIDENTIARY. Jurisdictional statutory-form waiver
///         requirements (e.g. Georgia O.C.G.A. section 44-14-366) must be satisfied
///         off-chain; waiverHash commits to that document.
contract DrawEscrow is EIP712, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ROLE_LENDER = keccak256("ROLE_LENDER");
    bytes32 public constant ROLE_SPONSOR = keccak256("ROLE_SPONSOR");
    bytes32 public constant ROLE_INSPECTOR = keccak256("ROLE_INSPECTOR");
    bytes32 public constant ROLE_PAUSER = keccak256("ROLE_PAUSER");

    /// @dev Basis points denominator. 10_000 bps = 100%.
    uint256 public constant BPS_DENOM = 10_000;

    /// @dev EIP-712 struct hash. Field order MUST match the Waiver struct in
    ///      IWaiverAttestor.sol exactly, or client-side viem digests won't match
    ///      contract-side hashWaiver() output. See hashWaiver() view.
    bytes32 public constant WAIVER_TYPEHASH = keccak256(
        "Waiver(bytes32 waiverHash,bytes32 projectId,uint256 milestoneId,uint256 drawNumber,uint256 throughAmount,uint8 kind,address claimant,uint256 issuedAt)"
    );

    IERC20 public immutable currency;
    MilestoneRegistry public immutable milestones;
    /// @dev Attestor is any EOA or ERC-1271 contract wallet. Verified via
    ///      SignatureChecker.isValidSignatureNow() which handles both paths.
    ///      NOT immutable: a title company employee's wallet may be lost or
    ///      rotated, and "redeploy" is not an acceptable answer when money is
    ///      inside. Rotation is two-step + timelock, lender-gated. Unrestricted
    ///      admin setter would recreate the Zoth key-compromise-to-redirection
    ///      failure mode, so we don't have one.
    address public attestor;
    address public pendingAttestor;
    uint256 public pendingAttestorEffectiveAt;
    /// @dev Timelock between proposeAttestorRotation and executeAttestorRotation.
    ///      Set at deploy so it appears in constructor args (deal-terms receipt)
    ///      rather than being a magic constant.
    uint256 public immutable attestorRotationDelay;

    bytes32 public immutable projectId;

    /// @dev Retainage held from each draw, expressed in bps. e.g. 1_000 = 10%.
    uint256 public immutable retainageBps;

    /// @dev Escrowed funds available to draw against.
    uint256 public totalFunded;
    uint256 public totalDrawn;
    uint256 public totalRetained;

    mapping(bytes32 => bool) public waiverConsumed;
    mapping(uint256 => uint256) public drawnPerMilestone;
    /// @dev Highest drawNumber consumed per milestone. Waivers must strictly
    ///      increment for their milestone (0, 1, 2, ...). This guards against
    ///      replay AND ensures the ledger has a coherent draw sequence.
    mapping(uint256 => uint256) public nextDrawNumber;

    event Funded(address indexed from, uint256 amount, uint256 totalFunded);
    event DrawReleased(
        uint256 indexed milestoneId,
        uint256 indexed drawNumber,
        address indexed payee,
        uint256 grossAmount,
        uint256 retained,
        uint256 net,
        bytes32 waiverDigest
    );
    event RetainageReleased(address indexed to, uint256 amount);
    event AttestorRotationProposed(address indexed proposer, address indexed pending, uint256 effectiveAt);
    event AttestorRotationExecuted(address indexed oldAttestor, address indexed newAttestor);
    event AttestorRotationCancelled(address indexed canceller, address indexed pending);

    error InsufficientFunds(uint256 requested, uint256 available);
    error WaiverAlreadyConsumed(bytes32 waiverDigest);
    error WaiverSignatureInvalid();
    error WaiverMilestoneMismatch(uint256 stepMilestone, uint256 waiverMilestone);
    error WaiverProjectMismatch(bytes32 expected, bytes32 got);
    error WaiverDrawNumberOutOfOrder(uint256 milestoneId, uint256 expected, uint256 got);
    error MilestoneNotAttested(uint256 milestoneId);
    error DrawExceedsMilestoneCap(uint256 milestoneId, uint256 requested, uint256 remaining);
    error ZeroAddress();
    error NoPendingRotation();
    error RotationTimelockNotElapsed(uint256 effectiveAt, uint256 nowTs);

    struct InitParams {
        address admin;
        address lender;
        address sponsor;
        address inspector;
        address currency;
        address milestones;
        address attestor;
        bytes32 projectId;
        uint256 retainageBps;
        // Seconds between proposeAttestorRotation and executeAttestorRotation.
        // Recorded in constructor args (deal terms). 24h suggested for demos;
        // production tenants pick their own based on operational risk profile.
        uint256 attestorRotationDelay;
    }

    constructor(InitParams memory p) EIP712("UnykornDrawEscrow", "1") {
        if (
            p.admin == address(0) ||
            p.lender == address(0) ||
            p.sponsor == address(0) ||
            p.inspector == address(0) ||
            p.currency == address(0) ||
            p.milestones == address(0) ||
            p.attestor == address(0)
        ) revert ZeroAddress();
        require(p.retainageBps <= BPS_DENOM, "retainage > 100%");

        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(ROLE_PAUSER, p.admin);
        _grantRole(ROLE_LENDER, p.lender);
        _grantRole(ROLE_SPONSOR, p.sponsor);
        _grantRole(ROLE_INSPECTOR, p.inspector);

        currency = IERC20(p.currency);
        milestones = MilestoneRegistry(p.milestones);
        attestor = p.attestor;
        projectId = p.projectId;
        retainageBps = p.retainageBps;
        attestorRotationDelay = p.attestorRotationDelay;
    }

    /// @notice Lender proposes a new attestor. Takes effect after
    ///         attestorRotationDelay seconds unless cancelled. The pending
    ///         attestor CANNOT sign valid waivers until execution.
    function proposeAttestorRotation(address newAttestor) external onlyRole(ROLE_LENDER) {
        if (newAttestor == address(0)) revert ZeroAddress();
        pendingAttestor = newAttestor;
        pendingAttestorEffectiveAt = block.timestamp + attestorRotationDelay;
        emit AttestorRotationProposed(msg.sender, newAttestor, pendingAttestorEffectiveAt);
    }

    /// @notice Cancel a proposed rotation. Available to lender at any time
    ///         before execution — key-compromise response path.
    function cancelAttestorRotation() external onlyRole(ROLE_LENDER) {
        emit AttestorRotationCancelled(msg.sender, pendingAttestor);
        pendingAttestor = address(0);
        pendingAttestorEffectiveAt = 0;
    }

    /// @notice Execute a proposed rotation once its timelock has elapsed.
    ///         From this block forward, the new attestor's signature validates
    ///         and the old attestor's does not.
    function executeAttestorRotation() external onlyRole(ROLE_LENDER) {
        if (pendingAttestor == address(0)) revert NoPendingRotation();
        if (block.timestamp < pendingAttestorEffectiveAt) {
            revert RotationTimelockNotElapsed(pendingAttestorEffectiveAt, block.timestamp);
        }
        address old = attestor;
        attestor = pendingAttestor;
        pendingAttestor = address(0);
        pendingAttestorEffectiveAt = 0;
        emit AttestorRotationExecuted(old, attestor);
    }

    /// @notice EIP-712 domain separator. Exposed so a client can cross-check its
    ///         locally-computed digest against the contract before ever asking
    ///         for a signature — that check reduces "invalid signature" reverts
    ///         to a one-line client-side error.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice EIP-712 digest for a Waiver. Client-side viem hashTypedData with
    ///         the same domain and Waiver typehash MUST return this exact bytes32.
    function hashWaiver(Waiver calldata w) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            WAIVER_TYPEHASH,
            w.waiverHash,
            w.projectId,
            w.milestoneId,
            w.drawNumber,
            w.throughAmount,
            uint8(w.kind),
            w.claimant,
            w.issuedAt
        )));
    }

    /// @notice Sponsor or lender funds the escrow with a given amount of currency.
    ///         Requires prior ERC-20 approve() from msg.sender.
    function fund(uint256 amount) external whenNotPaused {
        currency.safeTransferFrom(msg.sender, address(this), amount);
        totalFunded += amount;
        emit Funded(msg.sender, amount, totalFunded);
    }

    /// @dev Validation output packed into a single struct so releaseDraw stays under
    ///      the EVM 16-slot stack limit.
    struct _Validated {
        bytes32 waiverDigest;
        uint256 retained;
        uint256 net;
        uint256 alreadyDrawn;
    }

    function _validateDraw(
        uint256 milestoneId,
        uint256 grossAmount,
        Waiver calldata waiver,
        bytes calldata waiverSignature
    ) internal view returns (_Validated memory v) {
        if (waiver.projectId != projectId) {
            revert WaiverProjectMismatch(projectId, waiver.projectId);
        }
        if (waiver.milestoneId != milestoneId) {
            revert WaiverMilestoneMismatch(milestoneId, waiver.milestoneId);
        }
        {
            uint256 expectedDrawNumber = nextDrawNumber[milestoneId];
            if (waiver.drawNumber != expectedDrawNumber) {
                revert WaiverDrawNumberOutOfOrder(milestoneId, expectedDrawNumber, waiver.drawNumber);
            }
        }
        if (waiver.throughAmount < grossAmount) {
            revert DrawExceedsMilestoneCap(milestoneId, grossAmount, waiver.throughAmount);
        }
        (uint256 attestedThrough, bool attested) = milestones.attestedThrough(milestoneId);
        if (!attested) revert MilestoneNotAttested(milestoneId);
        v.alreadyDrawn = drawnPerMilestone[milestoneId];
        if (grossAmount + v.alreadyDrawn > attestedThrough) {
            revert DrawExceedsMilestoneCap(
                milestoneId,
                grossAmount,
                attestedThrough - v.alreadyDrawn
            );
        }
        v.waiverDigest = hashWaiver(waiver);
        if (waiverConsumed[v.waiverDigest]) revert WaiverAlreadyConsumed(v.waiverDigest);
        if (!SignatureChecker.isValidSignatureNow(attestor, v.waiverDigest, waiverSignature)) {
            revert WaiverSignatureInvalid();
        }
        v.retained = (grossAmount * retainageBps) / BPS_DENOM;
        v.net = grossAmount - v.retained;
    }

    /// @notice Releases a milestone draw to payee. Reverts unless (a) milestone is attested
    ///         at or above grossAmount, (b) the presented waiver is valid, unconsumed, and
    ///         references the correct projectId, milestoneId, and next drawNumber, and
    ///         (c) escrow has sufficient net-of-retainage funds.
    function releaseDraw(
        uint256 milestoneId,
        address payee,
        uint256 grossAmount,
        Waiver calldata waiver,
        bytes calldata waiverSignature
    ) external nonReentrant whenNotPaused onlyRole(ROLE_LENDER) {
        if (payee == address(0)) revert ZeroAddress();
        _Validated memory v = _validateDraw(milestoneId, grossAmount, waiver, waiverSignature);

        uint256 available = totalFunded - totalDrawn - totalRetained;
        if (grossAmount > available) revert InsufficientFunds(grossAmount, available);

        waiverConsumed[v.waiverDigest] = true;
        drawnPerMilestone[milestoneId] = v.alreadyDrawn + grossAmount;
        nextDrawNumber[milestoneId] = waiver.drawNumber + 1;
        totalDrawn += v.net;
        totalRetained += v.retained;

        currency.safeTransfer(payee, v.net);
        emit DrawReleased(
            milestoneId,
            waiver.drawNumber,
            payee,
            grossAmount,
            v.retained,
            v.net,
            v.waiverDigest
        );
    }

    /// @notice Releases accumulated retainage to a recipient. Lender-gated. Typically called
    ///         on substantial completion + presentation of a final unconditional waiver, which
    ///         SHOULD be recorded via releaseDraw with an UnconditionalFinal waiver first.
    function releaseRetainage(address to) external nonReentrant whenNotPaused onlyRole(ROLE_LENDER) {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = totalRetained;
        totalRetained = 0;
        currency.safeTransfer(to, amount);
        emit RetainageReleased(to, amount);
    }

    function pause() external onlyRole(ROLE_PAUSER) {
        _pause();
    }

    function unpause() external onlyRole(ROLE_PAUSER) {
        _unpause();
    }

    function available() external view returns (uint256) {
        return totalFunded - totalDrawn - totalRetained;
    }
}
