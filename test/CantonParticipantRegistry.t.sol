// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/registries/CantonParticipantRegistry.sol";

contract CantonParticipantRegistryTest is Test {
    CantonParticipantRegistry public cantonRegistry;
    address public admin = address(1);

    function setUp() public {
        vm.prank(admin);
        cantonRegistry = new CantonParticipantRegistry(admin);
    }

    function test_DefaultParticipants_BlackRock() public view {
        bytes32 partyId = keccak256("CANTON_BLACKROCK");
        CantonParticipantRegistry.Participant memory p = cantonRegistry.getParticipant(partyId);

        assertEq(p.name, "BlackRock");
        assertEq(uint256(p.participantType), uint256(CantonParticipantRegistry.ParticipantType.AssetManager));
        assertTrue(p.verified);
    }

    function test_RegisterNewParticipant() public {
        bytes32 newPartyId = keccak256("CANTON_NEW_BANK");

        vm.prank(admin);
        cantonRegistry.registerParticipant(
            "JPMorgan Canton Node",
            CantonParticipantRegistry.ParticipantType.Bank,
            "US",
            address(0x999),
            newPartyId
        );

        CantonParticipantRegistry.Participant memory p = cantonRegistry.getParticipant(newPartyId);
        assertEq(p.name, "JPMorgan Canton Node");
        assertTrue(p.verified);
    }
}
