# Playbook — Invoice Financing (B2B Receivables Factoring)

> Concrete end-to-end walkthrough for launching an invoice-financing facility against `InvoiceFactoringPool.sol`. Reference deal: a **B2B staffing / logistics receivables book** — the borrower vertical most consistently fundable in on-chain private credit because the debtors are large enterprises with predictable AP cycles.
>
> Related contract: [`InvoiceFactoringPool.sol`](../contracts/rwa/invoice-factoring/InvoiceFactoringPool.sol)
> Related landscape entry: [Invoice Factoring Pool (Centrifuge-shape)](../docs/index.html#invoice-factoring-pool)

---

## 0. Why invoice financing is the easiest RWA to launch first

Three properties make it fundable with the least friction:

1. **Self-liquidating on a 30-90 day cycle.** No principal amortization schedule, no valuation debates. The invoice pays face value at maturity or it doesn't; the write-off event is unambiguous.
2. **The debtor is the credit, not the borrower.** LPs underwrite the Fortune 1000 enterprise that receives the service, not the SMB that provides it. Same reason banks factor invoices against Amazon or FedEx AP but wouldn't lend unsecured to the staffing firm that services them.
3. **Loss data is public and standard.** DSO (days sales outstanding), dispute rates, and dilution rates for every major industry vertical are published quarterly by the Commercial Finance Association. LPs plug them into a standard credit model and get a number.

By contrast: real estate needs appraisals and 12+ month underwriting; private credit needs off-chain covenant monitoring; treasuries need SEC transfer-agent infrastructure. Invoice financing needs a well-formed invoice, a debtor lookup, and a bank wire.

---

## 1. The reference deal

**Borrower**: a mid-sized staffing agency ($40M annual revenue, 350 W-2 field employees) placing warehouse and logistics labor into 12 enterprise clients (top 5 = 78% of AR).

**Receivables book**:
- $6.5M average outstanding AR
- Weighted-average tenor: **45 days** (Net 30 with 15-day drift)
- Dispute rate: 1.8% of face
- Dilution (credits, chargebacks): 0.4% of face
- Bad debt: 0.15% of face (rolling 24-month)

**What the borrower needs**: to advance payroll every 2 weeks against invoices that pay in 45. Without factoring, they can't take on new clients; with factoring, they can grow ~30% per year.

**What the pool provides**: 85% advance rate on each approved invoice, 15% held back as reserve until the debtor pays. Yield to LPs comes from the discount between advance and face.

---

## 2. Legal structure

```
LP capital  ─┐
             ├──►  Delaware LLC (the SPV, a bankruptcy-remote entity)
Originator ──┘         │
                       │  owns the receivables outright via
                       │  Receivables Purchase Agreement (RPA)
                       ▼
                  Invoice pool
                       │
                       │  UCC-1 filed in Delaware naming the SPV as
                       │  secured party against the originator's
                       │  general intangibles
                       ▼
                  Perfected security interest
```

### 2.1 SPV formation
- **Delaware LLC** — same jurisdictional shell that Figure and Centrifuge use for receivables SPVs. Two-hour formation via Harvard Business Services or Stripe Atlas; $90 franchise tax.
- **Bankruptcy-remote clauses** in the Operating Agreement: independent director consent required for any voluntary bankruptcy filing, restrictions on merger, restrictions on incurring debt other than the pool facility.
- **EIN + operating bank account** at Mercury or Grasshopper Bank. This is the account that receives debtor payments before they're relayed on-chain.

### 2.2 Receivables Purchase Agreement (RPA)
The RPA is the **operative legal instrument**. The on-chain contract is the settlement + distribution layer. The RPA specifies:
- **True sale** language — receivables are sold, not pledged. Prevents recharacterization if the originator later files bankruptcy.
- **Repurchase obligation** on disputed or diluted invoices (the originator eats disputes, not the pool).
- **Notice-of-assignment (NOA) delivery** — whether the debtor is notified that payment now flows to the SPV's lockbox. Notified factoring reduces fraud risk; non-notified preserves the originator's customer relationship. Start with **notified** for the first pool; graduate to non-notified after 6-12 months of clean performance.
- **Servicing rights** — who collects, who reconciles, and what the standard of care is.

### 2.3 Perfection
File a **UCC-1 financing statement** with the Delaware Secretary of State (or the originator's home state if different) naming the SPV as secured party against the originator's accounts receivable + general intangibles. $20 filing fee. Store the file-stamped copy; on-chain, pin the SHA-256 of the filing PDF as the perfection anchor.

### 2.4 Token classification
The pool token (implicit — LP contribution tracked by `lpContribution` mapping) is a **participation interest in a debt fund**, not an equity security. Regulatory posture:
- **US LPs**: Regulation D 506(c) accredited-only offering. Register the pool via Form D within 15 days of the first sale.
- **Non-US LPs**: Regulation S offering. No SEC filing; 40-day distribution compliance period; enforce jurisdiction gating on the whitelist.

Either way, the pool token itself is not transferable to a non-whitelisted address (LP_ROLE-gated). Redemption via `lpClaim()` against the SPV.

---

## 3. Underwriting rules (published as the pool prospectus)

These become the pool's operating parameters. They're the single most-scrutinized document during LP due diligence.

| Parameter | Value | Rationale |
| --- | --- | --- |
| Minimum invoice size | **$5,000** | Below this, per-invoice overhead exceeds yield |
| Maximum invoice size | **$150,000** | Single-invoice concentration cap |
| Maximum concentration per debtor | **20% of pool face outstanding** | Diversify across the top 5 debtors |
| Approved debtor types | **US public companies (10-K filer) + top-100 US private companies by revenue** | Bloomberg/D&B verifiable credit |
| Maximum tenor | **90 days** (`maxTenorSec = 90 days` in constructor) | Anything longer is loan, not factoring |
| Advance rate | **85%** (`advanceRateBps = 8_500`) | Standard for prime debtors; 80% for weaker ones |
| Fee structure | **1.5% flat + 0.05%/day held** | Nets to ~3.75% yield at 45-day average tenor |
| Reserve holdback | **15%** (the face - advance spread) | Absorbs disputes, dilution, small write-offs |
| Approved industries | **Staffing, logistics, healthcare, B2B services** | Vertical concentration by *originator*, diversification by *debtor* |
| Dispute handling | **Originator repurchases within 5 business days** | RPA-enforced; failure to repurchase triggers pool default clause |
| Bad debt threshold | **>0.5% of pool face across trailing 90 days → pause origination** | Circuit breaker |

**Publish these numbers.** LPs will not fund a pool with vague underwriting; they will fund a pool with numeric limits they can model.

---

## 4. The three-stage funding funnel

Every RWA credit pool grows through the same three stages. Skip a stage and the raise breaks.

### Stage 1 — Anchor capital ($250K – $1M)
- **Source**: originator's own capital, a strategic family office, or a specialty lender who already factors this vertical off-chain.
- **Purpose**: prove the workflow. Fund 20-30 invoices, publish the loss data, generate the first 2 quarters of clean performance.
- **Terms**: often at a *higher* stated yield (8-12%) than what the pool will offer at scale, because early capital carries operational risk that later capital doesn't.

### Stage 2 — Repeatable pool capital ($1M – $10M)
- **Source**: accredited investors, DAO treasuries, specialty credit funds, on-chain fixed-income buyers.
- **Purpose**: scale AUM against proven performance. This is where the LP_ROLE whitelist starts admitting institutional wallets.
- **Terms**: fixed at the pool's published yield (typically 6-9% net of fees). LPs subscribe via `lpDeposit(amount)`.

### Stage 3 — Scalable distribution ($10M+)
- **Source**: Sky protocol / MakerDAO senior capital (via RWA vault), Centrifuge senior tranche buyers, tokenized-treasury desks looking for yield diversification.
- **Purpose**: bring the pool to institutional AUM. Requires 12+ months of performance data, an external audit, and typically graduation to a **tranched structure** (senior LPs + junior first-loss). At this point migrate from `InvoiceFactoringPool` to `BridgeLoanTranchePool`.

**Do not skip Stage 1.** LPs at Stage 2 explicitly ask "how much of your own capital is in the pool?" A pool with zero originator skin-in-the-game raises Stage 1 friends-and-family capital only.

---

## 5. Deploying the pool

### 5.1 Deploy `InvoiceFactoringPool.sol`

```solidity
new InvoiceFactoringPool({
    admin:              0x...,   // SPV admin multisig (BitGo Enterprise)
    originator:         0x...,   // Originator EOA or gnosis safe — calls originateInvoice() + writeOffInvoice()
    currency_:          0x...,   // USDC — ChainConstants.usdc(block.chainid)
    advanceRateBps_:    8_500,   // 85% advance rate
    maxTenorSec_:       90 days
});
```

### 5.2 Whitelist Stage-1 anchor investors

```solidity
pool.whitelistLP(anchorInvestor1);
pool.whitelistLP(anchorInvestor2);
```

The `LP_ROLE` gate is the entire investor eligibility layer for the pool. Off-chain, verify accredited status (US) or non-US jurisdiction (Reg S) before granting the role.

### 5.3 Anchor investors fund the pool

```solidity
usdc.approve(pool, amount);
pool.lpDeposit(amount);
```

`totalIdle` now reflects the available advance capital.

---

## 6. Per-invoice operating cycle

Each invoice moves through six deterministic steps. The originator's operations team runs steps 1-3 off-chain; steps 4-6 hit the contract.

### Step 1 — Borrower uploads invoice
Borrower's field ops team submits the invoice through the originator's portal: PDF of the invoice, debtor name, face value, due date, service delivery evidence (signed timesheet, BOL, delivery confirmation).

### Step 2 — Originator verifies + underwrites
- **Debtor lookup** against approved-debtor list. Reject if unlisted (or start a debtor-approval subprocess).
- **Concentration check** — will this invoice push the debtor above the 20% concentration cap?
- **Dispute check** — pull the borrower's rolling dispute rate; if trailing-30-day disputes >2% of face, hold new advances against this borrower pending investigation.
- **Verification call** — for invoices >$50K, a 5-minute AP-team call confirms the invoice was received, is undisputed, and is queued for payment.

### Step 3 — Notice of Assignment (first invoice per new debtor only)
If notified factoring, the originator sends a signed NOA to the debtor's AP department redirecting payment to the SPV lockbox. Track NOA acknowledgment. Do not advance until acknowledgment is received (usually 1-3 business days).

### Step 4 — Originate on-chain

```solidity
pool.originateInvoice(
    debtor:     0x...,          // A stable debtor address — can be a lookup key even if debtor isn't on-chain
    faceValue:  75_000e6,       // $75,000 in USDC
    dueDate:    block.timestamp + 45 days
);
```

The pool:
1. Verifies tenor is within `maxTenorSec` (90 days) — reverts if longer
2. Computes `advanceAmount = 75_000 * 8_500 / 10_000 = 63_750` USDC (85%)
3. Checks `totalIdle` has ≥ 63,750 USDC — reverts if pool is dry
4. Pushes the invoice into the `invoices` array with a synthesized `invoiceId`
5. Transfers 63,750 USDC to `msg.sender` (originator)
6. Emits `InvoiceOriginated(invoiceId, debtor, 75_000, 63_750, dueDate)`

The originator sweeps the USDC to their operating account and disburses payroll.

### Step 5 — Debtor pays

At maturity (45 days later in this example), the debtor wires or ACHs the face value to the SPV lockbox. The originator's ops team converts to USDC and calls:

```solidity
usdc.approve(pool, 75_000e6);
pool.payInvoice(invoiceId);
```

The pool:
1. Confirms the invoice isn't already `paid` or `written_off`
2. Pulls 75,000 USDC from `msg.sender`
3. Marks the invoice `paid = true`
4. Increments `totalIdle` by 75,000
5. Decrements `totalAdvanced` by 63,750
6. Decrements `totalFaceOutstanding` by 75,000
7. Adds `yieldEarned = 75_000 - 63_750 = 11_250` USDC to `totalDistributed`
8. Emits `InvoicePaid(invoiceId, 75_000, 11_250)`

### Step 6 — LPs claim yield

At any time, any LP can call:

```solidity
pool.lpClaim();
```

Which pays out their pro-rata share of `totalDistributed` minus what they've already claimed. Formula (contract-enforced):

```
entitled = lpContribution[lp] * totalDistributed / totalLPContributions
due      = entitled - lpClaimed[lp]
```

The `lpClaim()` call reverts with `InsufficientPoolLiquidity` if the pool's idle balance is below the amount due — LPs must wait until enough invoices mature to fund the claim. This is the intentional design that lets the pool operate without a first-loss tranche: LP redemption is naturally throttled by invoice maturity.

---

## 7. What happens if an invoice doesn't pay

Three failure modes, each with a specific playbook.

### 7.1 Dispute (most common — 1-2% of face)
The debtor withholds payment claiming the underlying service was not delivered or was defective. Under the RPA, the **originator is contractually required to repurchase the disputed invoice within 5 business days**. The originator pays face value back to the pool via `payInvoice(invoiceId)` — from the pool's perspective, indistinguishable from a normal payment. The originator then takes the dispute up with the debtor themselves.

If the originator fails to repurchase, the pool declares a **pool-level covenant default**, triggers the admin multisig to freeze new originations, and the LP whitelist enters wind-down mode (existing LPs claim, no new deposits accepted).

### 7.2 Slow pay (30-60 days past due)
Not a write-off — the invoice is still expected to pay. The originator's ops team runs standard AR collections: reminder emails at day 5, 15, 30 past due; escalation call to the debtor's AP director at day 45; formal demand letter at day 60. On-chain, the invoice remains `paid = false` and continues to sit on `totalFaceOutstanding`. `totalDistributed` doesn't grow, so LP yield stalls until it resolves.

Publish the aging report weekly. LPs care more about visibility than about slow pay itself — most factoring pools tolerate 5-8% of AR in 30-60 day buckets as normal.

### 7.3 Write-off (bad debt — <0.5% of face if underwriting is disciplined)
The debtor is not paying. Could be bankruptcy, could be a genuine dispute the originator lost. Originator calls:

```solidity
pool.writeOffInvoice(invoiceId);
```

Which:
1. Marks the invoice `written_off = true`
2. Decrements `totalAdvanced` by the advanced amount (63,750)
3. Decrements `totalFaceOutstanding` by the face value (75,000)
4. Emits `InvoiceWrittenOff(invoiceId, 63_750)`

**The 63,750 USDC is a real pool loss.** It shrinks LP entitlements proportionally because `totalDistributed` doesn't grow to compensate. In this simplified single-tranche pool, LPs eat the loss pro-rata to their contribution.

Two mitigations, both off-chain:
1. **Originator reserve account** — a separate fund the originator maintains (typically 2-5% of pool AUM) that manually reimburses write-offs before they hit LPs. Not enforceable on-chain in this contract; the promise is contractual.
2. **Graduate to `BridgeLoanTranchePool`** — the two-tranche version explicitly gives the originator a junior tranche that absorbs first loss on-chain. This is the natural next step once the pool crosses ~$5M AUM.

---

## 8. Yield economics — what the LP actually earns

Worked example: **$1M LP contribution into a fully-deployed pool, 45-day average tenor, 3% annualized loss rate.**

| Metric | Value | Formula |
| --- | --- | --- |
| Advance rate | 85% | `advanceRateBps / BPS_DENOM` |
| Spread per invoice | 15% of face | `1 - advanceRate` |
| Effective yield per cycle | 17.6% of advance | `spread / advance = 15/85` |
| Cycles per year | 8.1 | `365 / 45` |
| Gross yield annualized | 143% | Not realistic — advances turn over 8x/yr |
| Actual advance turnover | 8.1x | Same |
| Realistic annualized yield (gross) | **8.5-11%** | Reflects idle periods, dilution, dispute repurchase |
| Loss deduction | -3% | Bad debt + dilution |
| Fees to originator | -1.5% | Operational fee split |
| **Net yield to LP** | **~6-7%** | What actually shows up in `lpClaim()` |

This is the number that appears on the pool prospectus. Anything higher than ~8% net-to-LP on a first-year invoice-factoring pool is either underwriting shortcuts (accepting weak debtors), a first-loss buffer that's masking real losses, or accounting sleight-of-hand. Underpromise.

---

## 9. Costs to launch

| Item | Cost | Frequency |
| --- | --- | --- |
| Delaware LLC formation + registered agent | $250 + $150/yr | One-time + annual |
| RPA legal drafting (Katten, Latham, Reed Smith) | $8K-$15K | One-time |
| UCC-1 filing | $20 | Per debtor state |
| Regulatory counsel (Reg D or Reg S opinion) | $5K-$10K | One-time |
| BitGo Enterprise child profile | ~$1K/mo | Ongoing |
| Debtor verification (D&B, Bloomberg) | $500-$2K/mo | Ongoing |
| Ops staff (invoice verification, collections) | $60K-$120K/yr | Ongoing (originator side) |
| Audit (Trail of Bits, ConsenSys) for contract | $30K-$80K | Before Stage 3 |
| SEC Form D filing | $0 (self-file) | Once, within 15 days of first sale |

**Total to launch**: ~$25K legal + $30K ops runway = **$50K to first invoice originated**. This is the number to give any anchor investor as a use-of-funds.

---

## 10. Month-by-month execution

### Month 1 — Structure
- Form Delaware LLC (Day 1)
- Draft + execute RPA between originator and SPV
- File UCC-1 in originator's home state
- Open Mercury/Grasshopper operating account
- Deploy `InvoiceFactoringPool.sol` on Base or Polygon with anchor multisig as admin

### Month 2 — Stage 1 raise ($250K-$1M)
- Draft prospectus with published underwriting rules from Section 3
- Circulate to 3-5 friends-and-family + strategic investors
- Whitelist anchor addresses via `whitelistLP()`
- Anchor investors call `lpDeposit()` — pool is now fundable

### Month 3 — First invoices
- Onboard first 3 debtors (NOAs delivered + acknowledged)
- Originate first 5-10 invoices via `originateInvoice()`
- Publish weekly AR aging + concentration report

### Month 4-6 — Prove performance
- Continue originating; target $500K-$1M outstanding
- First `payInvoice()` cycles hit; `totalDistributed` grows
- First `lpClaim()` — anchor investors receive their first yield
- Publish first quarterly performance report

### Month 6-12 — Stage 2 raise ($1M-$10M)
- Open outreach to accredited investors + DAO treasuries + credit funds
- Update prospectus with first 6 months of actual loss data
- Grow whitelist; scale `totalLPContributions` 5-10x
- File amended Form D if needed

### Month 12+ — Stage 3 planning
- Commission external audit of `InvoiceFactoringPool.sol`
- Model the two-tranche graduation to `BridgeLoanTranchePool`
- Begin conversations with Sky protocol / Centrifuge for senior capital

---

## 11. Related contracts in this library

- **[`InvoiceFactoringPool.sol`](../contracts/rwa/invoice-factoring/InvoiceFactoringPool.sol)** — the pool itself.
- **[`BridgeLoanTranchePool.sol`](../contracts/rwa/bridge-loan-pool/BridgeLoanTranchePool.sol)** — graduation target once the pool crosses ~$5M AUM and needs a first-loss junior tranche.
- **[`PermissionedToken.sol`](../contracts/rwa/permissioned-security/PermissionedToken.sol)** — if the pool later issues a transferable participation token, this is the eligibility gate.
- **[`ProofOfReserveConsumer.sol`](../contracts/rwa/chainlink-proof-of-reserve/ProofOfReserveConsumer.sol)** — for Stage 3 institutional LPs who need a Chainlink attestation that pool assets ≥ outstanding obligations.
- **[`ChainConstants.sol`](../contracts/registries/ChainConstants.sol)** — canonical USDC address per chain for the pool's `currency_` constructor arg.

---

## 12. What this playbook is not

- **Not a legal opinion.** Every jurisdiction has specific factoring, usury, and securities requirements. The RPA, the UCC-1 filing strategy, and the Reg D/Reg S posture must be signed off by licensed counsel in each state where debtors sit.
- **Not a substitute for underwriting infrastructure.** The pool contract handles settlement + distribution. Off-chain, you need a debtor CRM, an invoice verification workflow, a collections team, and a lockbox banking relationship. Budget for that headcount before Stage 2.
- **Not a passive product.** Invoice financing is an operational business wearing a financial product's clothing. Originators who treat it as "deploy contract, collect fees" produce the losses that show up on rwa.xyz's writedown dashboards.

The reason invoice financing is the easiest RWA to *launch* is not that it's easy to *run* — it's that the failure modes are legible. A disciplined operator with a narrow vertical and published underwriting rules can compound this pool for a decade. An undisciplined one will lose 5-8% in the first 24 months and shut down.
