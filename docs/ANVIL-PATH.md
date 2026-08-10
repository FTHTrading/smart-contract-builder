# ANVIL PATH — Smart Contract Builder & smartcontract.unykorn.ai

Class: custody-chain | trading-rail
Owner: Kevan Burns (operator; sole gate authority)
Started: 2026-08-10
Status: G3 (BUILD & VERIFIED)

Rule zero: **no work in stage N+1 until gate GN carries a receipt** (`/anvil:gate GN`).
Gate passage is recorded in `.anvil/ops.receipts.jsonl` — the chain is the project's provenance, from intent to operation. A project with no gate receipts is, by definition, not launched.

---

## G0 — INTENT (kill it here or fund it here)

Exit criteria — all checked, evidence linked:
- [x] One-page thesis in `docs/INTENT.md`: Asset-tailored smart contract platform for RWA tokenization, private credit, tokenized treasuries, and sovereign namespaces. Monetized via setup fees ($5k-$25k), AUC servicing (10-25 bps), gate receipts ($500-$2.5k), and transfer agent fees.
- [x] Counterparty/dependency map: BitGo Custody, Chainlink Oracles/PoR/CCIP, Circle USDC, OpenZeppelin v5.0.2, EVM / XRPL / Stellar / Apostle networks.
- [x] Kill criteria written down: TVL floor < $1M after 120 days post-launch or unresolved security vulnerability in audited contracts.
- [x] Regulatory posture: Evidentiary settlement layer. Securities registration (Reg S / Reg D 506(c)), statutory form compliance (AIA G703), and custody transfer agent licensing covered by operating SPV entities and licensed custodial partners (BitGo Enterprise).
- [x] Named class overlays selected: `custody-chain` and `trading-rail`.

## G1 — SPEC

- [x] `/anvil:spec` run; `specs/rwa-builder.md` exists with cited current-state, invariants, and test plan.
- [x] Threat model section: Flash loan attack vectors, oracle manipulation/staleness, reentrancy on dividend pull accumulators, unauthorized identity minting.
- [x] Every invariant maps to a named test (`test/`).
- [x] Open questions answered by operator.

## G2 — PLAN

- [x] `/anvil:plan` run; ordered red-green-refactor steps in Foundry.
- [x] Every ⛔ OPERATOR GATE step identified (mainnet broadcasts, BitGo key signing, PoR feed configuration).
- [x] Definition of done for the build stage: 100% clean compilation under `solc 0.8.24` (`paris` EVM version), all invariant tests passing.

## G3 — BUILD

- [x] All contracts compile cleanly under `solc 0.8.24` with pinned OpenZeppelin 5.0.2 dependencies.
- [x] Invariant tests cover `DrawEscrow`, `CMBSWaterfall`, `REITDistributor`, `TokenizedTreasury`, `InvoiceFactoringPool`, `PermissionedToken`, `GoldBackedToken`.
- [x] No floats in financial paths; integer minor units (wei, drops, cents) end to end. Rounding directions documented.
- [x] Zero `TODO`/`FIXME` in shipped production paths.
- [x] Repo hygiene: `.anvil/ops.receipts.jsonl` initialized, zero secrets committed.

## G4 — AUDIT

- [ ] `/anvil:review` run on full diff; zero Critical/High open.
- [ ] Class-specific audit complete (Trail of Bits / ConsenSys Diligence / OpenZeppelin pass required prior to high-value mainnet TVL).
- [ ] Dependency review: OpenZeppelin v5.0.2 MIT licensed, pinned versions, no unverified third-party code.
- [ ] Failure-mode table in `docs/FAILURE-MODES.md`.

## G5 — DEPLOY

- [ ] Reproducible build: bytecode hashes matched against WASM compiler.
- [ ] Deploy receipt written to `.anvil/ops.receipts.jsonl`.
- [ ] Rollback rehearsed on Anvil local node / testnet.
- [ ] Secrets provisioned by operator only.

## G6 — LAUNCH

- [ ] `docs/RUNBOOK.md` complete with incident escalation.
- [ ] Monitoring live before users: Chainlink PoR circuit breakers, liveness alerts.
- [ ] Partner-facing walkthrough demo available on `smartcontract.unykorn.ai`.

## G7 — OPERATE (recurring, weekly)

- [ ] `/anvil:receipts` chain verifies weekly.
- [ ] Business metric vs. G0 thesis reviewed; AUC TVL tracked.
- [ ] CVE sweep on pinned dependencies.

---

# CLASS OVERLAYS

## Overlay: custody-chain (stablecoins, BitGo Express, XRPL Hooks/MPTs, ERC-3643, vaults)
- **G1 Addition**: Custody boundary diagram — Unykorn is never sole custodian; BitGo m-of-n enterprise custody handles underlying reserve assets.
- **G4 Addition**: Reentrancy, access control, oracle staleness, and compliance gate placement (KYC/sanctions checked *before* & *atomically with* value transfers).
- **G5 Addition**: Broadcast checklist — chainId verified, constructor args cross-checked against SPV deal terms; operator signs, never the agent.

## Overlay: trading-rail (FalconX, Osprey, OTC/settlement, neobank/MSB flows)
- **G1 Addition**: Settlement diagram — counterparty risk windows & netting rules.
- **G4 Addition**: Automated reconciliation (venue statements vs. internal ledger vs. bank/chain); idempotency on all transfers.
- **G5 Addition**: Sandbox → limits-capped production progression with per-day notional caps.
