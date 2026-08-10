// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DocumentRegistry
 * @notice Legal & Document Layer anchoring SHA-256 hashes and URIs for Offering Memorandums, Prospectuses, Custody Agreements, Audit Reports, Reserve Reports, and ISDA Documents.
 */
contract DocumentRegistry is AccessControl {
    bytes32 public constant DOCUMENT_ADMIN_ROLE = keccak256("DOCUMENT_ADMIN_ROLE");

    enum DocumentCategory {
        OfferingMemorandum,
        Prospectus,
        CustodyAgreement,
        AuditReport,
        ReserveAttestation,
        ComplianceReport,
        ISDADocument,
        FundLegalDoc
    }

    struct LegalDocument {
        bytes32 documentId;
        string assetOrEntitySymbol;
        DocumentCategory category;
        string documentTitle;
        bytes32 sha256Hash;
        string documentURI;
        uint256 timestamp;
        address uploader;
        bool active;
    }

    mapping(bytes32 => LegalDocument) public documents;
    bytes32[] public documentKeys;

    // assetOrEntitySymbol => documentIds
    mapping(string => bytes32[]) private symbolDocuments;

    event DocumentRegistered(bytes32 indexed documentId, string assetOrEntitySymbol, DocumentCategory indexed category, bytes32 sha256Hash);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DOCUMENT_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function registerDocument(
        string calldata assetOrEntitySymbol,
        DocumentCategory category,
        string calldata documentTitle,
        bytes32 sha256Hash,
        string calldata documentURI
    ) external onlyRole(DOCUMENT_ADMIN_ROLE) returns (bytes32 documentId) {
        documentId = keccak256(abi.encodePacked(assetOrEntitySymbol, category, documentTitle, block.timestamp));

        documents[documentId] = LegalDocument({
            documentId: documentId,
            assetOrEntitySymbol: assetOrEntitySymbol,
            category: category,
            documentTitle: documentTitle,
            sha256Hash: sha256Hash,
            documentURI: documentURI,
            timestamp: block.timestamp,
            uploader: msg.sender,
            active: true
        });

        documentKeys.push(documentId);
        symbolDocuments[assetOrEntitySymbol].push(documentId);

        emit DocumentRegistered(documentId, assetOrEntitySymbol, category, sha256Hash);
    }

    function getDocumentsForSymbol(string calldata symbol) external view returns (bytes32[] memory) {
        return symbolDocuments[symbol];
    }

    function _initializeDefaults() internal {
        bytes32 docId = keccak256("UNYKORN_CORPORATE_RESOLUTION_2026");
        documents[docId] = LegalDocument({
            documentId: docId,
            assetOrEntitySymbol: "UNYKORN",
            category: DocumentCategory.OfferingMemorandum,
            documentTitle: "Unykorn LLC Corporate Resolution & Asset Governance July 2026",
            sha256Hash: keccak256("UNYKORN_DOC_SHA256"),
            documentURI: "https://list.unykorn.ai/docs/CORPORATE_RESOLUTION_July2026.pdf",
            timestamp: block.timestamp,
            uploader: msg.sender,
            active: true
        });
        documentKeys.push(docId);
        symbolDocuments["UNYKORN"].push(docId);
    }
}
