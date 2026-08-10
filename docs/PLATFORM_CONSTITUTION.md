# Platform Constitution — Institutional Digital Asset Operating System Standards

This Constitution defines the non-negotiable architectural standards, governance rules, canonical identifier conventions, event standards, and operational definitions of "Done" for the **Unykorn Institutional Digital Asset Operating System** ([`smart-contract-builder`](https://github.com/FTHTrading/smart-contract-builder.git)).

---

## 🏛️ Article I: Non-Negotiable Architecture Standards

1. **8-Point Institutional CTO Validation Matrix**:
   No contract or module shall be merged or deployed without satisfying all 8 dimensions:
   * **Security**: Role-gated access control, pausable switches, reentrancy guards, circuit breakers.
   * **Governance**: Layer 13 proposal-based governance (`Proposal -> Review -> Approval -> Execution`).
   * **Auditability**: Cryptographic action logging (`Who, What, When, Why, Source, Hash`) via `AuditRegistry`.
   * **Regulation**: Universal LEI / BIC / ISO 20022 tracking and regulatory framework binding (`GENIUS`, `MiCA`, `MAS`).
   * **Testability**: 100% pass rate on Foundry unit & fuzz test suites plus automated deployment simulation.
   * **Upgradeability**: Version, implementation, and deprecation tracking via `ContractRegistry`.
   * **Observability**: Real-time health metrics, LCR, reserve ratios, and automated policy evaluation.
   * **Monetization**: General ledger accounting, yield routing, and settlement fee collection.

2. **The 13-Layer Master Operating System Hierarchy**:
   ```text
   13. Governance Layer       ─── GovernanceRegistry.sol
   12. Audit & Roles          ─── AuditRegistry.sol & GlobalRoleRegistry.sol
   11. Accounting & Ledger    ─── TreasuryLedger.sol (Double-Entry General Ledger)
   10. Treasury & Yield       ─── TreasuryPolicyEngine.sol & YieldRouter.sol
    9. Settlement Layer        ─── StablecoinSettlementHub.sol & PaymentRailRegistry.sol
    8. Valuation Layer         ─── ValuationOracle.sol & NAVOracle.sol
    7. Custody Layer           ─── CustodyRegistry.sol & CustodyAttestationRegistry.sol
    6. Assets Layer            ─── MultiChainRegistry.sol, RWARegistry.sol, ATP7332Registry.sol
    5. Participants Layer      ─── CantonParticipantRegistry.sol
    4. Regulation Layer        ─── RegulatoryFrameworkRegistry.sol
    3. Jurisdiction Layer      ─── JurisdictionManager.sol
    2. Compliance Layer        ─── ComplianceOracle.sol & SanctionsRegistry.sol
    1. Identity Layer          ─── GlobalIdentityRegistry.sol (LEI / BIC / ISO 20022)
   ```

---

## 🔑 Article II: Canonical Identifiers & Schema Mandates

1. **`bytes32` Primary Keys**:
   Assets, participants, identity profiles, policies, and documents shall never be referenced by raw string symbols alone. All production records must anchor to canonical `bytes32` primary keys:
   * `IdentityID` (`keccak256("UNYKORN_LLC")`)
   * `ParticipantID` (`keccak256("CANTON_BLACKROCK")`)
   * `AssetID` (`keccak256("USDF_SOVEREIGN_USD")`)
   * `CustodyID` (`keccak256("BNY_MELLON_CUSTODY")`)
   * `DocumentID` (`keccak256("CORPORATE_RESOLUTION_July2026")`)
   * `PolicyID` (`keccak256("INSTITUTIONAL_DEFAULT_POLICY")`)
   * `GovernanceID` (`keccak256("PROPOSAL_2026_01")`)

2. **Standardized Event Schema**:
   Every state-changing contract MUST emit standardized event signatures for indexers, analytics engines, and AI agents:
   * `event Created(...)`
   * `event Updated(...)`
   * `event Approved(...)`
   * `event Revoked(...)`
   * `event Audited(...)`

3. **Auditability & Registry Rules**:
   * Every state-changing action MUST trigger an `AuditRegistry.logAction(...)` entry.
   * No production asset, custodian, framework, or participant may exist in an unregistered state.

---

## 📋 Article III: The 11-Point Definition of "Done"

An object or asset is declared institutionally complete when it can answer all 11 operational queries:
1. **Who owns it?** → Verified via `GlobalIdentityRegistry` & `IdentityID`.
2. **Who issued it?** → Attributed via `MultiChainRegistry` issuer metadata.
3. **Who verified it?** → Validated via `ComplianceOracle` & `IdentityRegistry`.
4. **Who custodies it?** → Mapped via `CustodyRegistry` & `CustodyAttestationRegistry`.
5. **What is it worth?** → Priced via `ValuationOracle` & `NAVOracle`.
6. **What regulations apply?** → Bound via `RegulatoryFrameworkRegistry` (`GENIUS`, `MiCA`, `MAS`).
7. **What risks exist?** → Evaluated via `RiskEngine` concentration & counterparty checks.
8. **Who approved it?** → Approved via `GovernanceRegistry` (Layer 13 Proposal).
9. **What documents govern it?** → Anchored via `DocumentRegistry` SHA-256 legal hashes.
10. **How is it settled?** → Routed via `StablecoinSettlementHub` & `PaymentRailRegistry`.
11. **How is it audited?** → Hash-chained via `AuditRegistry` & process-G ops receipts.

---

## 🚀 Article IV: Strategic Focus & Productization Roadmap

Going forward, engineering effort is focused on **operationalization, automation, and productization**:
* **Phase 1: Operationalization**: Automated Foundry multi-chain deployments, OpenAPI 3.0 REST Gateway (`openapi.yaml`), and webhook web portals.
* **Phase 2: Productization**: Treasury Console, Compliance Console, Custody Dashboard, and Risk Analytics APIs.
* **Phase 3: Autonomous AI Layer**: AI Treasury & Settlement Agents orchestrating `WorkflowEngine` and `PolicyEngine` executions.
