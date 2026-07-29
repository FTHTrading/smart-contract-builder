# Smart Contract Builder

> Real Solidity for real-world-asset workflows. Every contract compiles clean under a pinned solc + vendored OpenZeppelin, ships with tests, and is drivable end-to-end from the [Unykorn Studio](https://github.com/FTHTrading/unykorn-studio) console with a hash-chained audit trail per action.

<p>
  <a href="./LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-navy.svg"></a>
  <a href="#build--test"><img alt="Solidity 0.8.24" src="https://img.shields.io/badge/Solidity-0.8.24-blue.svg"></a>
  <a href="#build--test"><img alt="Foundry" src="https://img.shields.io/badge/Foundry-latest-orange.svg"></a>
  <a href="https://fthtrading.github.io/smart-contract-builder/"><img alt="Docs" src="https://img.shields.io/badge/Docs-catalog-green.svg"></a>
  <img alt="Status: v0.5" src="https://img.shields.io/badge/Status-v0.5-lightgrey.svg">
</p>

**Live catalog:** https://fthtrading.github.io/smart-contract-builder/ · **Ecosystem landscape:** https://fthtrading.github.io/smart-contract-builder/landscape.html

---

## Table of Contents

- [What this is](#what-this-is)
- [What this is not](#what-this-is-not)
- [The catalog](#the-catalog)
  - [🏢 Real Estate / Structured Finance](#-real-estate--structured-finance)
  - [🏦 Private Credit / Institutional Lending](#-private-credit--institutional-lending)
  - [💵 Tokenized Funds](#-tokenized-funds)
  - [🏠 Real Estate (Debt + Equity)](#-real-estate-debt--equity)
  - [🏛 Securities / Compliance](#-securities--compliance)
  - [🌱 ESG / Climate / Sovereignty](#-esg--climate--sovereignty)
  - [🔗 Oracles / Cross-chain](#-oracles--cross-chain)
  - [📋 Chain Registries](#-chain-registries)
- [Deal playbooks](#deal-playbooks)
- [Ecosystem landscape](#ecosystem-landscape)
- [Build & test](#build--test)
- [Deploying against a real chain](#deploying-against-a-real-chain)
- [Extending the library](#extending-the-library)
- [Videos](#videos)
- [Related repos](#related-repos)
- [License](#license)

---

## What this is

A **Foundry project** containing production-shaped Solidity contracts for the RWA workflows Unykorn actually ships against:

- Construction draw escrow (Georgia statutory-form waiver evidence layer)
- ERC-3643-inspired permissioned security tokens
- REIT NOI distribution (accumulator-pattern pull dividends)
- CMBS 3-tranche waterfall (senior / mezz / equity)
- SREC token (ERC-1155, EIP-712 meter attestation)
- Chainlink oracle consumer (AggregatorV3 with staleness + heartbeat guards)
- Chainlink Proof of Reserve consumer (circuit breaker over mint)
- Chainlink CCIP bridged token (burn-and-mint cross-chain)
- Pool Delegate lending pool (Maple Finance-shape institutional lending)
- Invoice factoring pool (Centrifuge Tinlake-shape short-tenor receivables)
- Bridge loan tranche pool (Centrifuge two-tranche senior/junior with Sky protocol composability)
- Inventory financing SPV (single-asset ABL with UCC-1 lien + tranche waterfall — $2M EV charger reference deal)
- Tokenized mortgage / HELOC (Figure-shape ERC-20 claim on a single loan)
- Fractional property equity (RealT / Lofty-shape SPV shares with rental distribution + sale redemption)
- Tokenized treasury / MMF (BUIDL / OUSG / USYC shape with PoR-gated mint)
- Cash management vault (ERC-4626 allocator with reserve ratio)
- Gold-backed token (PAXG-shape commodity RWA with LBMA-vault PoR)

Every contract is **real Solidity, not a snippet**. Every one compiles clean under `solc 0.8.24` with `evmVersion: paris` and OpenZeppelin v5.0.2. Every one is drivable end-to-end through Unykorn Studio's approval-per-step executor with a SHA-256 hash-chained receipt written for every state transition.

Design philosophy in one line: **the contract is the settlement layer; the legal document is the instrument.** Everything here is engineering scaffolding that produces cryptographic evidence — not a substitute for the legal, compliance, and audit work that a live deployment requires.

## What this is not

- **Not audited.** No external security audit has been performed. Do not deploy any contract in this repo to a chain holding real funds without a licensed audit.
- **Not a legal opinion.** Every contract that touches a regulated instrument (waivers, securities, carbon credits) is clearly labeled as evidentiary, not dispositive. Statutory-form conformity, securities registration, and tax posture are the responsibility of licensed counsel in the operating jurisdiction.
- **Not a token generator.** Studio's product is the audit chain, not the token. If you need a copy-paste ERC-20 wizard, use OpenZeppelin Wizard. If you need to prove who authorized what deployment with what bytecode from what compile, use this stack.

---

## The catalog

Every contract family below has been extracted from Unykorn Studio's shipped templates. Each ships with:

- **Real Solidity source** (compilable, natspec-documented)
- **Studio integration** — a template plan that walks write → compile → deploy → configure with typed-confirm gates on irreversible steps
- **Hash-chained receipts** — every state transition written to Studio's append-only JSONL ledger

### 🏢 Real Estate / Structured Finance

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [Draw Escrow (Georgia)](./contracts/rwa/draw-escrow/) | ✅ SHIPPED | `IWaiverAttestor` (types) · `MilestoneRegistry` · `DrawEscrow` · `LocalTestToken` | 6.6 KB + 3.2 KB | Payment-and-waiver coupled release, EIP-712 attestor signing (EOA or ERC-1271), two-step timelocked attestor rotation, AIA G703 milestone mapping. Reference deployment: M Helen Hotel LLC SPV. |
| [REIT NOI Distribution](./contracts/rwa/reit-distribution/) | ✅ SHIPPED | `DistributionToken` · `REITDistributor` | 4.4 KB + 4.5 KB | Pull-based per-unit dividends via accumulator pattern (MasterChef-style). `_update` hook settles debt on transfer; late claimers always get exactly their entitled share. |
| [CMBS 3-Tranche Waterfall](./contracts/rwa/cmbs-tranche/) | ✅ SHIPPED | `CMBSWaterfall` | 5.5 KB | Senior / mezz / equity distribution priorities with simple-interest accrual. Default: senior 7% · mezz 11% · equity residual. |

### 🏦 Private Credit / Institutional Lending

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [Pool Delegate Pool (Maple-shape)](./contracts/rwa/private-credit-pool/) | ✅ SHIPPED | `PoolDelegatePool` | ~12 KB | Curated credit marketplace. Pool Delegate underwrites borrowers, sets concentration limits, posts first-loss capital. Whitelist-gated lenders. Cooldown-protected redemptions. Same shape Maple uses for its $2B+ active-loan book. |
| [Invoice Factoring Pool (Centrifuge-shape)](./contracts/rwa/invoice-factoring/) | ✅ SHIPPED | `InvoiceFactoringPool` | ~10 KB | Short-term receivables (30-90 day tenor). Advance rate 80-90% at origination; face value at maturity funds LP yield. Same shape Centrifuge Tinlake uses for supply-chain finance + invoice pools. |
| [Bridge Loan Tranche Pool (Centrifuge Tinlake-shape)](./contracts/rwa/bridge-loan-pool/) | ✅ SHIPPED | `BridgeLoanTranchePool` | ~10 KB | Two-tranche pool. Originator retains junior (first loss), on-chain investors buy senior (fixed APY). Ongoing origination against a rolling loan book. Senior tranche freely transferable so it composes with Sky protocol (formerly MakerDAO) for USDS-collateralized borrowing — the mechanism that funded 85%+ of Centrifuge-originated loans historically. |
| [Inventory Financing SPV](./contracts/rwa/inventory-financing/) | ✅ SHIPPED | `InventoryFinancingSPV` | ~11 KB | Single-asset asset-backed loan. UCC-1 lien hash pinned on-chain. Senior/junior tranche funding, amortizing repayment with waterfall. Reference deal: $2M EV chargers in a Tennessee warehouse — see [playbook](./playbooks/inventory-financing-ev-chargers.md). |

### 💵 Tokenized Funds

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [Tokenized Treasury / MMF](./contracts/rwa/tokenized-treasury/) | ✅ SHIPPED | `TokenizedTreasury` | ~9 KB | BUIDL / BENJI / OUSG / USYC shape. PermissionedToken-gated receiver, PoR circuit breaker on mint, NAV-priced subscription/redemption, T+N settlement queue. Composes with our PermissionedToken + ProofOfReserveConsumer via interface hooks. |
| [Cash Management Vault](./contracts/rwa/cash-management/) | ✅ SHIPPED | `CashManagementVault` | ~7 KB | ERC-4626-shape vault. Deposits USDC, allocator rebalances into yield-bearing RWA shares (BUIDL/USYC/BENJI) while maintaining a minimum reserve ratio for instant redemptions. Reference shape: Maple Cash Management, Anchorage cash sweep. |

### 🏠 Real Estate (Debt + Equity)

Two orthogonal ways to put real estate on-chain — a claim on the loan's cash flow (debt) vs a claim on the property's economic upside (equity). Both are shipped; pick the one that matches the deal.

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [Tokenized Mortgage / HELOC (Figure-shape)](./contracts/rwa/real-estate-debt/) | ✅ SHIPPED | `RealEstateDebtToken` | ~9 KB | Fungible ERC-20 claim on a single mortgage or HELOC. Servicer records monthly P+I payments; accumulator pattern distributes pro-rata to holders. Mortgage note hash + deed hash + property address hash pinned on-chain as evidentiary anchors (physical note remains the operative legal instrument). Reference: Figure Technology Solutions — $18B+ tokenized HELOCs + mortgages on Provenance Blockchain. |
| [Fractional Property Equity (RealT-shape)](./contracts/rwa/fractional-property/) | ✅ SHIPPED | `FractionalPropertyToken` | ~10 KB | Fungible fractional SPV shares in a single property. Property manager deposits net rental income at configured cadence; accumulator pattern distributes to holders. On property sale, sponsor deposits proceeds and holders redeem their tokens for pro-rata cash. Eligibility-gated transfers (Reg S non-US retail or Reg D 506(c) US accredited depending on required claim topics). Reference: RealT, Lofty — U.S. residential properties tokenized as SPV shares with daily USDC rental distribution. |

### 🏛 Securities / Compliance

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [Permissioned Security Token](./contracts/rwa/permissioned-security/) | ✅ SHIPPED | `IdentityRegistry` · `ClaimTopicsRegistry` · `PermissionedToken` | 2.7 KB + 2.4 KB + 6.6 KB | ERC-3643-inspired. Receiver-eligibility check on every transfer via KYC + claim-topic gates. Freeze-tokens + force-transfer for legal remedies. Pauseable. |

### 🌱 ESG / Climate / Sovereignty

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [SREC Token](./contracts/rwa/srec-token/) | ✅ SHIPPED | `SRECToken` | 11 KB | ERC-1155. 1 SREC = 1 MWh. Mint requires EIP-712 attestation from the registered meter agent. Vintage + state encoded in token ID. Burn = retirement with reason string. Settlement layer, not a replacement for PJM-GATS / NEPOOL-GIS / WREGIS. |
| [Gold-Backed Token (PAXG-shape)](./contracts/rwa/gold-backed/) | ✅ SHIPPED | `GoldBackedToken` | ~8 KB | Commodity RWA. 1 token = 1 troy oz (4 decimals). Mint gated by PoR circuit breaker against LBMA-vault attestations. Redemption for physical: burn on-chain, physical shipment off-chain via reserve manager. |
| [On-chain Carbon Retirement](#) | 🟠 DESIGN | *(pending Toucan / Moss / Puro integration)* | — | Burn a bridged Verra VCU (Toucan on Polygon) or issue-native Puro credit (ERC-3643). LPS-1 provenance receipt anchored to Polygon 137 + Bitcoin OpenTimestamps. |

### 🔗 Oracles / Cross-chain

| Contract family | Status | Contracts | Bytecode | Notes |
| --- | --- | --- | --- | --- |
| [Chainlink Oracle Consumer](./contracts/rwa/chainlink-oracle/) | ✅ SHIPPED | `RWAOracle` | 3.4 KB | Wraps Chainlink `AggregatorV3Interface` with 4 safety checks: non-negative answer, complete round, staleness, heartbeat. |
| [Chainlink Proof of Reserve](./contracts/rwa/chainlink-proof-of-reserve/) | ✅ SHIPPED | `ProofOfReserveConsumer` | ~5 KB | Reads PoR feed, drives circuit breaker over mint. Same pattern 21.co (ARK BTC ETF), Backed, Bedrock, Bancolombia use in production. |
| [Chainlink CCIP Bridged Token](./contracts/rwa/chainlink-ccip-bridge/) | ✅ SHIPPED | `CCIPBridgedToken` | ~8 KB | ERC-20 with cross-chain burn-and-mint via Chainlink CCIP. Zero liquidity-pool risk, unified supply across 70+ chains. Peer whitelist for security. |
| [XRPL Hooks + Stellar SEP](#) | 🟠 DESIGN | *(pending adapter subprocesses)* | — | XRPL Hooks in C for XRPL-native lending flows. Stellar SEP-based assets for cross-border settlement. Multi-chain expansion. |

### 📋 Chain Registries

| Registry | Status | Contents |
| --- | --- | --- |
| [ChainConstants](./contracts/registries/ChainConstants.sol) | ✅ SHIPPED | Canonical mainnet addresses per chain: USDC + USDT (Circle, Tether), Chainlink CCIP router + chain selectors, LINK token, ETH/USD price feeds. Ethereum, Polygon, Base, Arbitrum, Optimism, Avalanche, BNB. |

---

## Ecosystem landscape

See [`docs/landscape.html`](./docs/landscape.html) (or the [live version](https://fthtrading.github.io/smart-contract-builder/landscape.html)) for a full ecosystem map covering:

- **Chainlink stack** — Data Feeds, Data Streams, SmartData, Proof of Reserve, CCIP, ACE (Automated Compliance Engine), DECO (privacy-preserving ZKP oracle), CRE (Chainlink Runtime Environment)
- **Tokenized private credit market leaders** — Figure ($18–20B), Maple ($5B AUM), Centrifuge ($430M+ + Janus JTRSY), Goldfinch (Goldfinch Prime), Securitize (SEC-registered transfer agent for BUIDL + Apollo)
- **20+ live TradFi–DeFi integrations** — Swift + UBS via CCIP, ANZ Project Guardian, HSBC + Ant Group, BlackRock + Uniswap, Franklin Templeton + Ondo, Nasdaq + Kraken, ICE + OKX, Canton Network (DTCC + LSEG + Euroclear)
- **Where Unykorn fits** — substrate not product, Chainlink integration not replacement, open library not walled garden

See also [`docs/integrations.html`](./docs/integrations.html) ([live version](https://fthtrading.github.io/smart-contract-builder/integrations.html)) — **every provider the library needs to operate correctly**, with per-integration status:

- **Custody**: BitGo Enterprise (primary) · Anchorage · Fireblocks · Fidelity · Coinbase Custody · Standard Custody
- **Compliance / KYC**: Chainlink ACE · ONCHAINID · Securitize · Chainalysis · TRM Labs · Elliptic · Persona · Onfido · Jumio · Trulioo · Sumsub · Chainlink DECO (ZKP)
- **Data / Oracles**: Chainlink Data Feeds + Streams + PoR + SmartData + Automation + CRE · Pyth · RedStone · API3 · Umbrella
- **Settlement**: USDC (Circle) · USDT (Tether) · USDF (UnyKorn) · PYUSD (PayPal) · RLUSD (Ripple)
- **Cross-chain**: Chainlink CCIP · LayerZero · Wormhole · Axelar
- **Funders**: BlackRock · Franklin Templeton · Apollo · Janus Henderson · Swift · UBS · HSBC · DBS · Canton Network consortium · **Maple Pool Delegates** ([BlockTower](./docs/integrations.html#blocktower) — also the largest Centrifuge originator with $220M+ RWA on-chain / Room40 / AQRU) · **MakerDAO / Sky** (senior capital provider — $150M into BlockTower's Centrifuge pools, historically funded 85%+ of Centrifuge origination via RWA vault USDS-collateral mechanism) · Centrifuge · Goldfinch · Ondo · Clearpool · TrueFi · Robinhood · Kraken · Binance · OKX · Public.com
- **LD Capital / UnyKorn stack**: LD Capital · M Helen Hotel LLC SPV · Water Park at Helen · UnyKorn 7777 INC

---

## Deal playbooks

Concrete end-to-end walkthroughs of real deals against the contract library — legal structure, funding venue selection, term sheet, constructor calls, week-by-week execution, default enforcement realism.

- [Inventory Financing: $2M EV chargers in a Tennessee warehouse](./playbooks/inventory-financing-ev-chargers.md) — Delaware LLC formation, Centrifuge vs Maple funding venue comparison, senior/junior tranche stack ($1.6M senior at 900 bps + $320K junior first-loss), 18-month amortizing term, constructor payload for `InventoryFinancingSPV`, UCC-1 filing checklist, month-by-month execution timeline, realistic 6-18 month enforcement path with 50-80% recovery expectation.
- [Invoice Financing: B2B receivables factoring](./playbooks/invoice-financing.md) — the easiest RWA to launch first. Delaware SPV + Receivables Purchase Agreement + UCC-1, published underwriting rules (advance rate, concentration caps, dispute handling), three-stage funding funnel (anchor → repeatable → Sky/Centrifuge scale), constructor payload for `InvoiceFactoringPool`, per-invoice 6-step operating cycle, dispute vs slow-pay vs write-off failure playbooks, realistic 6-7% net LP yield economics.

More playbooks will land against `CMBSWaterfall` (M Helen Hotel refinance), `RealEstateDebtToken` (single-HELOC issuance), and `PoolDelegatePool` (curated credit onboarding).

---

## Build & test

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
# Install OpenZeppelin dependencies (v5.0.2 pinned)
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-git

# Compile all contracts
forge build

# Run tests (when tests are added — see roadmap)
forge test -vv

# Deploy a single contract against a local Anvil
anvil --host 127.0.0.1 --port 8545 --chain-id 31337 &
forge script script/Deploy<Name>.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

**Determinism settings** (frozen — do not change without a bytecode diff review):

```toml
[profile.default]
solc_version = "0.8.24"
optimizer = true
optimizer_runs = 200
evm_version = "paris"
bytecode_hash = "ipfs"
via_ir = false
```

Same settings as Unykorn Studio's compile pipeline. Contract bytecode compiled here is byte-for-byte identical to what Studio compiles via its self-hosted WASM worker.

---

## Deploying against a real chain

None of these contracts have been externally audited. Before any deployment holding real funds:

1. **External security audit.** Trail of Bits, ConsenSys Diligence, OpenZeppelin, Sherlock, Code4rena — pick based on capability and budget.
2. **Static + dynamic analysis.** Slither + Mythril + Foundry fuzz + invariant testing.
3. **Sign externally.** Deployment through Unykorn Studio's `sign_external` step (BitGo hand-off). Studio never holds testnet or mainnet keys.
4. **Verify on Etherscan / Sourcify.** `metadata.bytecodeHash: ipfs` in the compile settings makes verification straightforward.
5. **Bug bounty.** Immunefi or HackenProof, commensurate with TVL.

Every contract has been *designed* to be audit-friendly (single-purpose, minimal external calls, explicit custom errors) — but designed-to-be-audit-friendly is not the same as audited.

---

## Extending the library

New contract family in ~30 minutes:

1. Add `contracts/rwa/<family>/*.sol` — real, compilable Solidity.
2. Register in Studio's `lib/templates/<family>/{sources.ts,template.ts}` (either extract from the .sol files at build time or duplicate — Studio's compile receipt hashes the standard-JSON input, so the two just need to match byte-for-byte).
3. Add a capability entry in Studio's `lib/intent/capabilities.ts` with regex matches, tier-varied param questions, decision cards.
4. Add a section to `docs/index.html` in this repo with status badge + specs table.

If adding a new step kind (e.g. `configure_roles`, `verify_source`), also:

5. Extend `AgentStepKind` union in Studio's `app/store.ts`.
6. Add label + color in `AgentLane.tsx`.
7. Add to `IRREVERSIBLE` in `lib/intent/gates.ts` if the action can't be undone.
8. Wire a handler in `useExecutor.ts`.

**No other changes required.** If a new capability needs to modify Studio's executor dispatch, receipt hash logic, or gate mechanics, that is a design bug in the abstraction — not a routine change.

---

## Videos

Short explainer videos are being produced against each contract family. Scripts and storyboards live in [`videos/`](./videos/) — record via OBS or Loom, publish to YouTube, embed in the docs site.

- [Overview: what this library is and isn't](./videos/00-overview.md) — 4 min
- [Draw Escrow: the M Helen use case](./videos/01-draw-escrow.md) — 7 min
- [Permissioned Securities: ERC-3643 without T-REX complexity](./videos/02-permissioned-security.md) — 6 min
- [Carbon Portfolio: subprocess bridge as abstraction test](./videos/03-carbon-portfolio.md) — 5 min
- [The tamper beat: proving the ledger is not editable](./videos/04-tamper-beat.md) — 3 min

---

## Related repos

- **[unykorn-studio](https://github.com/FTHTrading/unykorn-studio)** — the console that drives these contracts through an approval-per-step executor with hash-chained receipts. The product; this library is the substrate.
- **[unykorn-carbon](https://github.com/FTHTrading/unykorn-carbon)** — portfolio carbon accounting + SREC valuation engine. Carbon Portfolio Assessment capability in Studio calls this via subprocess bridge.
- **[LDX](https://github.com/FTHTrading/LDX)** — LD Capital / LDX public site (post-quantum Rust core + M Helen deal artifacts).
- **[Donkai](https://github.com/FTHTrading/Donkai---1977)** — satirical Layer-1 (unrelated but ships against the same LPS-1 provenance standard).

---

## License

[MIT](./LICENSE) — Kevan Burns · UnyKorn LLC · Wyoming EIN 42-3536633.
