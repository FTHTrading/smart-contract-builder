// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title SRECToken
/// @notice One-MWh Renewable/Solar Energy Credit. Mint requires an EIP-712
///         attestation signed by the registered generator's meter agent
///         (typically the utility, PJM-GATS agent, or the site's data logger).
///         Burn is retirement; emits a Retirement event with the reason.
contract SRECToken is ERC1155, EIP712, AccessControl {
    using SignatureChecker for address;

    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    bytes32 public constant METER_ATTESTATION_TYPEHASH = keccak256(
        "MeterAttestation(bytes32 generatorId,uint16 vintageYear,bytes32 state,uint256 mwhGenerated,uint256 nonce,uint256 issuedAt)"
    );

    /// generatorId → registered meter attestor (EOA or ERC-1271 contract)
    mapping(bytes32 => address) public meterAttestor;
    /// generatorId → last nonce consumed (monotonic)
    mapping(bytes32 => uint256) public generatorNonce;
    /// tokenId → total supply (for reporting; ERC1155 doesn't track this by default)
    mapping(uint256 => uint256) public totalSupply;
    /// tokenId → retired supply
    mapping(uint256 => uint256) public totalRetired;

    event GeneratorRegistered(bytes32 indexed generatorId, address indexed meterAttestor);
    event GeneratorRemoved(bytes32 indexed generatorId);
    event SRECMinted(bytes32 indexed generatorId, uint256 indexed tokenId, address indexed to, uint256 mwh, uint256 nonce);
    event Retirement(uint256 indexed tokenId, address indexed retirer, uint256 amount, string reason);

    error UnknownGenerator(bytes32 generatorId);
    error AttestationInvalid();
    error NonceOutOfOrder(uint256 expected, uint256 got);

    constructor(address admin, string memory uri_) ERC1155(uri_) EIP712("SRECToken", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function registerGenerator(bytes32 generatorId, address attestor) external onlyRole(REGISTRAR_ROLE) {
        meterAttestor[generatorId] = attestor;
        emit GeneratorRegistered(generatorId, attestor);
    }

    function removeGenerator(bytes32 generatorId) external onlyRole(REGISTRAR_ROLE) {
        delete meterAttestor[generatorId];
        emit GeneratorRemoved(generatorId);
    }

    /// @notice Compose (vintage, state, region) into a single uint256 token id
    ///         so downstream buyers can filter on any of them.
    function tokenIdFor(uint16 vintageYear, bytes32 state) public pure returns (uint256) {
        return (uint256(vintageYear) << 240) | (uint256(state) >> 16);
    }

    struct MeterAttestation {
        bytes32 generatorId;
        uint16 vintageYear;
        bytes32 state;
        uint256 mwhGenerated;
        uint256 nonce;
        uint256 issuedAt;
    }

    function hashAttestation(MeterAttestation calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            METER_ATTESTATION_TYPEHASH,
            a.generatorId,
            a.vintageYear,
            a.state,
            a.mwhGenerated,
            a.nonce,
            a.issuedAt
        )));
    }

    /// @notice Mint SRECs matching a meter reading. Signature is over
    ///         MeterAttestation typed data by the generator's registered attestor.
    function mintFromMeter(
        MeterAttestation calldata attestation,
        bytes calldata signature,
        address to
    ) external {
        address attestor = meterAttestor[attestation.generatorId];
        if (attestor == address(0)) revert UnknownGenerator(attestation.generatorId);
        uint256 expectedNonce = generatorNonce[attestation.generatorId];
        if (attestation.nonce != expectedNonce) revert NonceOutOfOrder(expectedNonce, attestation.nonce);
        bytes32 digest = hashAttestation(attestation);
        if (!attestor.isValidSignatureNow(digest, signature)) revert AttestationInvalid();

        uint256 tokenId = tokenIdFor(attestation.vintageYear, attestation.state);
        totalSupply[tokenId] += attestation.mwhGenerated;
        generatorNonce[attestation.generatorId] = expectedNonce + 1;

        _mint(to, tokenId, attestation.mwhGenerated, "");
        emit SRECMinted(attestation.generatorId, tokenId, to, attestation.mwhGenerated, attestation.nonce);
    }

    /// @notice Retire SRECs — burns them. Reason string is emitted for the
    ///         audit trail. Common reasons: "voluntary offset FY2026",
    ///         "compliance NJ RPS Q1 2026", "customer #42 offset opt-in".
    function retire(uint256 tokenId, uint256 amount, string calldata reason) external {
        totalRetired[tokenId] += amount;
        _burn(msg.sender, tokenId, amount);
        emit Retirement(tokenId, msg.sender, amount, reason);
    }

    /// @notice Batch retirement across multiple vintages/states in one tx.
    function retireBatch(uint256[] calldata tokenIds, uint256[] calldata amounts, string calldata reason) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalRetired[tokenIds[i]] += amounts[i];
            emit Retirement(tokenIds[i], msg.sender, amounts[i], reason);
        }
        _burnBatch(msg.sender, tokenIds, amounts);
    }

    // Required by ERC1155 + AccessControl multi-inheritance
    function supportsInterface(bytes4 interfaceId)
        public view virtual override(ERC1155, AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
