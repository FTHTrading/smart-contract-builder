// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MomentRelicVault
 * @notice Multi-token vault contract for Unykorn's 9 Moment Relics and 60 Athlete Generational Trust Fund namespaces.
 */
contract MomentRelicVault is ERC1155, AccessControl {
    using Strings for uint256;

    bytes32 public constant CUSTODIAN_ROLE = keccak256("CUSTODIAN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct MomentRelic {
        uint256 relicId;
        string name;
        bytes32 assetHash;
        uint256 valuationUSD;
        bool lockedInVault;
    }

    mapping(uint256 => MomentRelic) public relics;
    string public baseURI;

    event RelicMinted(uint256 indexed relicId, string name, uint256 valuationUSD, address indexed beneficiary);
    event RelicValuationUpdated(uint256 indexed relicId, uint256 newValuationUSD);
    event RelicVaultStatusChanged(uint256 indexed relicId, bool isLocked);

    error RelicDoesNotExist(uint256 relicId);

    constructor(string memory initialURI, address admin) ERC1155(initialURI) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CUSTODIAN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        baseURI = initialURI;
    }

    function mintRelic(
        uint256 relicId,
        string calldata name,
        bytes32 assetHash,
        uint256 valuationUSD,
        address beneficiary,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        relics[relicId] = MomentRelic({
            relicId: relicId,
            name: name,
            assetHash: assetHash,
            valuationUSD: valuationUSD,
            lockedInVault: true
        });

        _mint(beneficiary, relicId, amount, "");
        emit RelicMinted(relicId, name, valuationUSD, beneficiary);
    }

    function setRelicValuation(uint256 relicId, uint256 newValuationUSD) external onlyRole(CUSTODIAN_ROLE) {
        if (relics[relicId].relicId == 0) revert RelicDoesNotExist(relicId);
        relics[relicId].valuationUSD = newValuationUSD;
        emit RelicValuationUpdated(relicId, newValuationUSD);
    }

    function setRelicVaultStatus(uint256 relicId, bool isLocked) external onlyRole(CUSTODIAN_ROLE) {
        if (relics[relicId].relicId == 0) revert RelicDoesNotExist(relicId);
        relics[relicId].lockedInVault = isLocked;
        emit RelicVaultStatusChanged(relicId, isLocked);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
