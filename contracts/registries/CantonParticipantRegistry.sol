// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CantonParticipantRegistry
 * @notice Canton Network Institutional Participant Registry tracking Banks, Asset Managers, Broker-Dealers, Custodians, Exchanges, Funds, and Sovereigns.
 */
contract CantonParticipantRegistry is AccessControl {
    bytes32 public constant CANTON_ADMIN_ROLE = keccak256("CANTON_ADMIN_ROLE");

    enum ParticipantType {
        Bank,
        AssetManager,
        BrokerDealer,
        Custodian,
        Exchange,
        Fund,
        Sovereign
    }

    struct Participant {
        string name;
        ParticipantType participantType;
        string jurisdiction;
        address primaryAccount;
        bytes32 cantonPartyId;
        bool verified;
        bool active;
    }

    mapping(bytes32 => Participant) public participants;
    bytes32[] public participantKeys;

    event ParticipantRegistered(bytes32 indexed partyId, string name, ParticipantType pType, string jurisdiction);
    event ParticipantUpdated(bytes32 indexed partyId, bool verified, bool active);

    error ParticipantAlreadyExists(bytes32 partyId);
    error ParticipantNotFound(bytes32 partyId);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CANTON_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerParticipant(
        string calldata name,
        ParticipantType participantType,
        string calldata jurisdiction,
        address primaryAccount,
        bytes32 cantonPartyId
    ) external onlyRole(CANTON_ADMIN_ROLE) {
        if (participants[cantonPartyId].active) revert ParticipantAlreadyExists(cantonPartyId);

        participants[cantonPartyId] = Participant({
            name: name,
            participantType: participantType,
            jurisdiction: jurisdiction,
            primaryAccount: primaryAccount,
            cantonPartyId: cantonPartyId,
            verified: true,
            active: true
        });

        participantKeys.push(cantonPartyId);
        emit ParticipantRegistered(cantonPartyId, name, participantType, jurisdiction);
    }

    function updateParticipantStatus(
        bytes32 cantonPartyId,
        bool verified,
        bool active
    ) external onlyRole(CANTON_ADMIN_ROLE) {
        if (participants[cantonPartyId].cantonPartyId == bytes32(0)) revert ParticipantNotFound(cantonPartyId);

        participants[cantonPartyId].verified = verified;
        participants[cantonPartyId].active = active;

        emit ParticipantUpdated(cantonPartyId, verified, active);
    }

    function getParticipant(bytes32 cantonPartyId) external view returns (Participant memory) {
        if (!participants[cantonPartyId].active) revert ParticipantNotFound(cantonPartyId);
        return participants[cantonPartyId];
    }

    function _initializeDefaults() internal {
        _addParticipant("BlackRock", ParticipantType.AssetManager, "US", keccak256("CANTON_BLACKROCK"));
        _addParticipant("Franklin Templeton", ParticipantType.AssetManager, "US", keccak256("CANTON_FRANKLIN"));
        _addParticipant("Ripple", ParticipantType.BrokerDealer, "US", keccak256("CANTON_RIPPLE"));
        _addParticipant("Circle", ParticipantType.BrokerDealer, "US", keccak256("CANTON_CIRCLE"));
        _addParticipant("Paxos", ParticipantType.BrokerDealer, "US", keccak256("CANTON_PAXOS"));
        _addParticipant("Unykorn", ParticipantType.Sovereign, "US", keccak256("CANTON_UNYKORN"));
        _addParticipant("DTCC", ParticipantType.Custodian, "US", keccak256("CANTON_DTCC"));
        _addParticipant("Goldman Sachs", ParticipantType.Bank, "US", keccak256("CANTON_GOLDMAN"));
        _addParticipant("BNY Mellon", ParticipantType.Custodian, "US", keccak256("CANTON_BNY_MELLON"));
        _addParticipant("Broadridge", ParticipantType.Exchange, "US", keccak256("CANTON_BROADRIDGE"));
    }

    function _addParticipant(
        string memory name,
        ParticipantType pType,
        string memory jurisdiction,
        bytes32 partyId
    ) internal {
        participants[partyId] = Participant({
            name: name,
            participantType: pType,
            jurisdiction: jurisdiction,
            primaryAccount: address(0),
            cantonPartyId: partyId,
            verified: true,
            active: true
        });
        participantKeys.push(partyId);
    }
}
