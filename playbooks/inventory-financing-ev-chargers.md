# Playbook — Tokenized Inventory Financing for $2M EV Chargers (Tennessee Warehouse)

**Situation**: You hold ~$2M in EV charger inventory in a Tennessee warehouse. You need working capital to fund sales, distribution, and operational expenses while the inventory sells down. You want to use the physical inventory as collateral for an on-chain-funded loan rather than a traditional bank ABL (asset-based lending) facility.

**This playbook**: end-to-end walkthrough. Legal structure, contract selection, funding platform choice, disbursement, repayment, and — critically — what happens if you default.

> This is a real playbook for a real deal. Nothing here is legal or tax advice. Every step involving statutory filings (UCC-1), securities exemption claims, or SPV formation requires a licensed attorney in the state of the collateral and the state of the SPV.

---

## Table of contents

- [The one contract you'll use](#the-one-contract-youll-use)
- [Legal structure (must happen before any code)](#legal-structure-must-happen-before-any-code)
- [Choose a funding venue: Centrifuge vs Maple](#choose-a-funding-venue-centrifuge-vs-maple)
- [Term sheet parameters](#term-sheet-parameters)
- [Step-by-step execution](#step-by-step-execution)
- [What happens if you default](#what-happens-if-you-default)
- [Costs breakdown](#costs-breakdown)
- [Timeline](#timeline)

---

## The one contract you'll use

**[InventoryFinancingSPV.sol](../contracts/rwa/inventory-financing/InventoryFinancingSPV.sol)** — single-asset asset-backed loan. Not a pool. One SPV, one loan, one collateral pile, one UCC-1 lien.

Key fields the contract stores on-chain for the audit trail:

| Field | What it holds | Why it matters |
| --- | --- | --- |
| `collateralDescription` | "300 units EV Level 2 chargers, model X, serialized" | Ties the loan to a specific inventory pile, not a category |
| `collateralLocation` | "Warehouse ABC, 1234 Main St, Chattanooga, TN 37402" | Identifies where the physical enforcement happens |
| `uccLienHash` | keccak256 of the executed UCC-1 filing document | Proves the paper document existed at loan origination |
| `uccFilingState` | "TN" | Which secretary of state to petition for enforcement |
| `uccFilingNumber` | State's assigned filing number | Cross-reference to the state's public UCC search |

**None of these fields substitutes for the paper UCC-1 filing itself.** They record that the filing happened. Enforcement remains through Tennessee's civil courts and the Tennessee Secretary of State's UCC office.

---

## Legal structure (must happen before any code)

### 1. Form the SPV

- **Entity**: Delaware LLC. (Delaware because it's the widely-accepted jurisdiction for SPV securities work; Tennessee is where the collateral sits, not where the SPV lives.)
- **Purpose clause**: single-purpose, single-transaction. "The purpose of this LLC is to hold and finance a pool of EV charger inventory located at [address] and to service the obligations under a secured loan facility documented as [reference]."
- **Non-consolidation**: standard SPV bankruptcy-remote covenants — no cross-obligations with your operating company, no comingling of funds, independent director requirement for major decisions.
- **Cost**: ~$500 filing + ~$500/yr registered agent + $2-5K legal drafting for a first SPV, less for subsequent ones off the same template.

### 2. Transfer the inventory to the SPV

- **Bill of sale** from your operating company to the SPV for the $2M of chargers.
- **Warehouse control agreement** with the storage facility acknowledging the SPV as the owner.
- **Insurance policy** naming the SPV as the loss payee on the inventory.

### 3. Execute the loan documents

- **Master loan agreement** — terms, interest rate, maturity, covenants.
- **Security agreement** — grants the lenders a security interest in "all EV charger inventory now held or hereafter acquired by the SPV."
- **UCC-1 financing statement** — filed with the Tennessee Secretary of State. This is the public notice that gives lenders priority over subsequent creditors.
- **Note or debt instrument** — the actual promise to repay, potentially tokenized as the senior tranche shares.

### 4. Establish operational bank accounts

- SPV opens a bank account at a US institution (or a stablecoin-native cash management setup — BitGo Enterprise, Anchorage, or a Circle Business account).
- All revenue from inventory sales must flow into this account, not into your operating company's account, or you break the SPV's isolation.

---

## Choose a funding venue: Centrifuge vs Maple

### Centrifuge (recommended for this shape)

**Why it fits:**
- Purpose-built for securitizing off-chain assets — trade finance, invoices, inventory, real estate bridge loans. Your EV chargers are exactly this asset class.
- Two-tranche architecture (senior/junior) matches what our `InventoryFinancingSPV.sol` implements.
- Junior tranche retention by the originator (you) is the standard model — Centrifuge investors expect it.
- Deep DeFi integration: senior tranche tokens can be posted as collateral in Sky (formerly Maker) to borrow USDS. Over 85% of Centrifuge-originated loans have historically been financed this way, which means senior tranche liquidity is deeper than the platform's direct investor pool suggests.

**Who funds you:**
- Sky protocol's USDS liquidity (indirectly, via a Sky vault posting your senior tranche tokens as collateral).
- Direct on-chain investors (whitelisted, KYC'd) buying senior tranche shares.

**Typical senior tranche APY:** 7-14% depending on collateral quality, tenor, and market conditions.

**Onboarding time:** 4-12 weeks for a first-time originator. Centrifuge's credit team performs off-chain diligence on you, the collateral, the SPV structure, and the servicer.

### Maple Finance (alternative)

**Why it might fit:**
- Direct corporate borrowing model. You pitch a **Pool Delegate** (BlockTower, Room40, AQRU-style professional credit officer) who underwrites you directly.
- Maple recently established a landmark on-chain warehouse facility for Kraken's OTC lending desk — same shape, same platform.
- If a Pool Delegate approves you, funding is fast (days after approval).

**Why it might NOT fit:**
- Maple's institutional lending pools typically overcollateralize corporate loans at 105-130% in liquid crypto assets (BTC, ETH, SOL). Physical inventory as collateral is less standard for them.
- The Pool Delegate has to want your deal specifically; you're pitching one credit officer, not an underwriting protocol.

**Typical rate:** 10-16% depending on the Pool Delegate's assessment.

**Onboarding time:** 2-6 weeks to Pool Delegate approval; funding within a week after.

### Recommendation

**Centrifuge**, because your deal shape (physical inventory + SPV + senior/junior tranche + UCC-1) is what they were built for. Maple is the fallback if Centrifuge's credit team declines or the terms don't clear.

---

## Term sheet parameters

Concrete numbers for your $2M deal, using the `InventoryFinancingSPV.sol` constructor:

| Parameter | Suggested value | Reasoning |
| --- | --- | --- |
| **Total loan** | $1,600,000 (80% of $2M) | Standard advance rate against inventory collateral. Leaves 20% equity cushion. |
| **Junior tranche (yours)** | $320,000 (20% of loan) | Centrifuge norm. Enough skin-in-the-game to align incentives but doesn't consume your working capital. |
| **Senior tranche (on-chain)** | $1,280,000 (80% of loan) | Sold to whitelisted Centrifuge senior investors or via Sky-collateralized borrow. |
| **Senior interest rate** | 900 bps (9% APY) | Middle of Centrifuge's typical inventory-backed range. |
| **Term** | 18 months (47,304,000 seconds) | Long enough to sell down the inventory; short enough that lenders can price the risk. Amortizing repayment. |
| **Junior yield** | Residual (whatever's left after senior gets paid) | If you sell inventory faster than plan, you keep the upside. |
| **Amortization** | Monthly interest-only for months 1-6, then P+I amortizing through month 18 | Gives you runway to build the sales pipeline before principal payments kick in. |

Constructor call (Studio-driven):

```
InventoryFinancingSPV.InitParams({
    admin: 0x[deployer],
    borrower: 0x[your borrower wallet],
    legalAgent: 0x[SPV legal agent — could be same as admin],
    currency: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,  // USDC on Ethereum
    seniorTarget: 1_280_000_000_000,   // 1.28M USDC (6 decimals)
    juniorBps: 2_000,                   // 20%
    seniorRateBps: 900,                 // 9%
    termSec: 47_304_000                 // 18 months
})
```

Then the four setup calls:

```
recordCollateral(
    "300 units EV Level 2 chargers, model X, serialized",
    "Warehouse ABC, 1234 Main St, Chattanooga, TN 37402",
    keccak256("<PDF bytes of the UCC-1 filing>"),
    "TN"
)
confirmUCCFiling("2026-1234567")       // TN Secretary of State assigns this
postJuniorCapital(320_000_000_000)      // your 320k USDC deposit
// Whitelisted senior lenders then call fundSenior() until seniorRaised == seniorTarget.
// At full funding, principal auto-transfers to your wallet.
```

---

## Step-by-step execution

### Week 1-2: Legal structure
- Form Delaware LLC (~$500 + $2-5K legal).
- Bill of sale, security agreement, master loan agreement drafted.
- Warehouse control agreement + insurance endorsement.
- **Deliverable**: signed loan documents + SPV formation kit.

### Week 3-4: UCC-1 filing + Centrifuge onboarding
- File UCC-1 with Tennessee Secretary of State (~$25 + attorney time).
- Submit application to Centrifuge with SPV formation docs, financials, collateral inventory list, and servicer information.
- **Deliverable**: assigned UCC-1 filing number + Centrifuge credit committee agenda slot.

### Week 5-8: Centrifuge underwriting
- Centrifuge credit team performs diligence: your operating company financials, EV charger sales pipeline, warehouse audit, insurance verification.
- Terms negotiated on-chain (rate, senior cap, amortization schedule).
- **Deliverable**: signed term sheet from Centrifuge.

### Week 9-10: Deploy + fund
- Deploy `InventoryFinancingSPV` via Unykorn Studio's approval-per-step flow. Every step writes a hash-chained receipt.
- Call `recordCollateral` — records the UCC lien hash on-chain.
- Call `confirmUCCFiling` — transitions to Funding phase.
- Post your $320K junior capital via `postJuniorCapital`.
- Whitelisted senior lenders subscribe via `fundSenior` until $1.28M raised.
- At full funding, principal transfers to your wallet.
- **Off-ramp**: convert USDC to USD via Circle Business account or Coinbase Prime. Deposit into your operating bank.
- **Deliverable**: $1.6M in your operating account.

### Ongoing: monthly service
- You sell EV chargers, collect USD in your operating account.
- Convert USD → USDC (Circle mint, ~1-2 business days for institutional).
- Call `repay(amount)` monthly. Contract waterfalls the payment: senior interest → senior principal → junior residual.
- Senior lenders call `claimSenior()` to withdraw their share; you call `claimJunior()` to withdraw yours.
- Every repayment writes a hash-chained receipt.

### Month 18: payoff or refinance
- If fully repaid: contract auto-transitions to `Repaid` phase. UCC-1 must be released (file UCC-3 termination statement with TN SoS).
- If not fully repaid: negotiate an extension or refinance. Contract stays in `Active` phase; senior interest continues to accrue.

---

## What happens if you default

**This is the part that gets glossed over in every crypto pitch. Read it twice.**

### What the smart contract does

- `declareDefault(reason)` — legal agent calls this. Phase transitions to `Defaulted`. `DefaultDeclared` event emits with the outstanding principal and reason string.
- **That's it.** The smart contract does not seize the warehouse. It does not lock the doors. It does not auction the EV chargers.

### What lenders actually do

- Their claim is the UCC-1 filed with the Tennessee Secretary of State. That lien gives them priority over subsequent unsecured creditors.
- To enforce, they file a lawsuit in the Tennessee court where your SPV is registered to do business (or where the collateral sits).
- The court authorizes seizure of the collateral.
- A licensed auctioneer sells the inventory.
- Proceeds pay: (1) auction costs; (2) senior lenders' outstanding principal + interest; (3) junior tranche (you); (4) any remaining to unsecured creditors.

### Why this matters for how you underwrite the deal

- **Time to recovery**: 6-18 months from default to sale of collateral, in a Tennessee civil court.
- **Recovery rate**: 50-80% of face value on physical inventory at forced sale. Depending on how liquid EV chargers are as a secondary market.
- **Senior lender protection**: with 20% junior tranche, senior lenders are protected against up to a 20% loss on the collateral before they take a hit. That's why they charge 9% instead of 15%.

### What Unykorn Studio does that traditional ABL doesn't

- Every step from origination through repayment through default declaration is a hash-chained receipt. If there's ever a dispute about what was authorized, when, or by whom, the receipt log is the record.
- The UCC-1 hash on-chain means any lender can independently verify the paper filing they were shown at origination matches what's committed on-chain.
- Repayment receipts are cryptographically linked. If you dispute the waterfall math in a workout, both sides have the same authoritative record.

---

## Costs breakdown

| Item | Cost | Recurring? |
| --- | --- | --- |
| Delaware LLC formation | $500 filing + $500/yr registered agent | Annual |
| Legal drafting (SPV + loan docs + UCC-1) | $3,000 - $10,000 first time; $2K after | One-time |
| TN UCC-1 filing | $25 + attorney time | One-time |
| Centrifuge underwriting fee | 0.5% - 2% of principal, paid at origination | One-time |
| Servicing agent | 0.25% - 0.5% of outstanding principal, annualized | Ongoing |
| Circle Business / Coinbase Prime off-ramp | 0.05% - 0.15% per conversion | Per transaction |
| Insurance | 0.5% - 1.5% of collateral value, annualized | Annual |
| Chainlink Proof of Reserve (optional, adds monitoring) | ~$5K-15K setup + oracle gas | One-time + ongoing |

**Total upfront cost estimate**: $10,000 - $25,000 to originate the deal.
**Total recurring annualized cost**: 0.75% - 1.5% of outstanding principal + insurance.

**Compare to traditional ABL**: 5-year facility with a regional bank runs 2-4% arrangement fee, 0.5% commitment fee on undrawn, 8-14% interest, plus quarterly reporting requirements. On-chain financing is competitive on total cost and materially faster on speed to funding after the first deal.

---

## Timeline

```
Week 1  ─┬─ Form SPV, execute loan docs
        │
Week 2  ─┼─ Sign warehouse control agreement, transfer inventory
        │
Week 3  ─┼─ File UCC-1 in TN, submit to Centrifuge
        │
Week 5  ─┼─ Centrifuge diligence begins
        │
Week 7  ─┼─ Term sheet signed
        │
Week 9  ─┼─ Deploy contract, record collateral, confirm UCC filing
        │
Week 10 ─┼─ Post junior tranche, senior fundraise, principal disbursed
        │
Month 4 ─┼─ First interest-only payment (assumes month 3 = origination + 30 days grace)
        │
Month 9 ─┼─ Amortization begins (P+I)
        │
Month 18 ─┴─ Payoff or refinance
```

**Total from first legal call to money in your operating account**: 10-14 weeks first deal; 4-6 weeks for subsequent deals under the same template.

---

## Next-deal templating

Once the first deal closes, everything except the collateral-specific details (description, location, UCC hash, filing number) is a template. Subsequent deals against the same or similar collateral types can:

1. Reuse the SPV structure documents.
2. Deploy a new `InventoryFinancingSPV` with the same InitParams shape.
3. Use the same Centrifuge senior investor whitelist.
4. Repeat.

This is the productization surface. The first deal is the setup investment; every subsequent deal is a template call.

---

## Related contracts in this library

- **[PoolDelegatePool](../contracts/rwa/private-credit-pool/PoolDelegatePool.sol)** — if you want to pool multiple inventory-financing deals into a single lender-facing pool.
- **[BridgeLoanTranchePool](../contracts/rwa/bridge-loan-pool/BridgeLoanTranchePool.sol)** — Centrifuge's own two-tranche pool contract shape, if you want to originate against multiple asset classes simultaneously.
- **[ProofOfReserveConsumer](../contracts/rwa/chainlink-proof-of-reserve/ProofOfReserveConsumer.sol)** — if you want to layer continuous PoR attestation of the inventory count as an additional lender safeguard.
- **[PermissionedToken](../contracts/rwa/permissioned-security/PermissionedToken.sol)** — if the senior tranche shares need to be transferable to other whitelisted investors post-origination.

---

*Playbook v1.0 · not legal advice · every step involving statutory filings, securities exemption claims, or SPV formation requires a licensed attorney in the state of the collateral and the state of the SPV.*
