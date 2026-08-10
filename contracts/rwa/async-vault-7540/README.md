# Async Vault — ERC-7540 + ERC-8161

Canonical async request-based vault (ERC-7540), extended with transferable pending deposit and redeem requests (ERC-8161).

**Status:** SHIPPED — compiles clean, unaudited until external audit engagement (same posture as the rest of this library).

**Standards:**
- ERC-7540 (async subscription/redemption queues, single canonical `requestId`)
- ERC-8161 (transferable pending requests — Feb 2025, authored by Centrifuge's CTO)

**Contracts:**
- `AsyncVault7540.sol` — the vault, inherits the mixin
- `../../mixins/ERC7540Transferable.sol` — reusable ERC-8161 mixin
- `../../interfaces/IERC7540Transferable.sol` — canonical interfaces

**Interface IDs (ERC-165):**
- `0x53b3bb0a` — `IERC7540DepositTransferable`
- `0x7846f5bd` — `IERC7540RedeemTransferable`

---

## The problem ERC-8161 solves — the "stuck in line" problem

Every ERC-7540 fund works like a subscription queue: an investor commits $250K, but shares don't appear instantly — the request sits **pending** until the next NAV strike or settlement window (a day, sometimes a week). During that window, under plain 7540, the investor is frozen. They can't sell the position (it doesn't exist yet), can't move it to another wallet, and if they cancel to fix anything, they lose their place in the queue and start over.

ERC-8161 makes the **place in line itself a transferable asset**. The pending $250K subscription becomes something the investor can sell, gift, or move — before it ever settles.

---

## Use case map — 21 concrete uses across three sides of the market

### Investor-side

1. **Pre-settlement exit** — sell a pending subscription for cash before NAV strike instead of being locked for the queue period.
2. **Wallet migration** — hot wallet → multisig/cold storage mid-queue, one transaction, queue position preserved.
3. **Account restructuring** — move a pending position into a trust, family LLC, or spouse's verified wallet without cancel/resubmit.
4. **KYC re-papering** — investor's wallet gets re-verified under a new entity; position transfers to the new address without losing priority.
5. **Family-office consolidation** — sweep pending positions from multiple sub-accounts into one master account.
6. **Late-wire rescue** — investor's fiat lands T+2 but the queue closes today; an affiliate takes the slot now, transfers it to the investor when funds arrive.

### Liquidity-desk side (the arbitrage & market-making surface)

7. **Queue-discount arbitrage** — buy pending subscriptions at a discount to expected settlement value, hold to settlement, capture the discount. Factoring, applied to fund queues.
8. **Redemption factoring** — the mirror trade: buy pending redemptions at a discount from sellers who want cash today; collect full NAV at settlement.
9. **NAV-drift capture** — on a T-bill sleeve, NAV accrues predictably at the short rate. If pending positions trade at prices that lag the deterministic accrual, the drift is free carry.
10. **Cross-market relative value** — price pending positions against the settled share trading on secondary venues; buy whichever is cheap relative to settlement value.
11. **Hedged carry** — buy discounted pending redeems, hedge the underlying exposure via futures until settlement; discount minus hedge cost is near-market-neutral carry.
12. **Capital rotation** — exit a pending position in vault A to fund an opportunity in vault B immediately, without burning a cancel/settle cycle.
13. **Two-way market-making** — quote continuous bid/offer on pending positions; earn the spread.
14. **Syndication anchor** — a desk anchors a large subscription at launch, then distributes pieces to syndicate members via transfers as they complete KYC.

### Issuer-side (vault economics)

15. **Transfer-fee revenue** — configurable `transferFeeBps` skimmed on secondary transfers; paid only by parties who value the liquidity (default 0, hard-capped at 100 bps in this reference implementation).
16. **Product differentiation** — "you are never locked, even mid-settlement" against traditional fund lockups.
17. **Bulletin-board venue** — the issuer can host the matching surface where sellers meet buyers; fee both sides.
18. **Pending-position lending** — accept pending requests as loan collateral at a haircut (transfer into an escrow contract as the pledge).
19. **Operational rescue** — compliance-gated fix for subscriptions sent from the wrong wallet, without breaking the queue.
20. **Treasury mobility** — the issuer's own seed positions move between series/SPV wallets freely.
21. **Distribution-partner tooling** — RIAs and brokers reallocate client pending positions during onboarding transitions.

---

## Worked scenarios

### Scenario 1 — the liquidity exit

Investor has $250K pending in the T-bill sleeve, 5-day settlement, needs cash for an unrelated closing. A liquidity desk bids **99.60**. Investor gets $249,000 today; the desk collects ~$250K + accrual at settlement. Desk nets ~40 bps in 5 days; issuer skims 25 bps transfer fee (~$625). Three parties, three outcomes: investor bought liquidity, desk bought carry, issuer sold the rail.

### Scenario 2 — redemption factoring

A family office has $1M pending redemption, 7-day queue, and a margin call elsewhere. Desk buys the pending redeem at **99.0** — $990K wired today. At settlement the desk collects $1M: ~$10K gross over 7 days, minus hedge cost if the desk shorts the exposure via futures in the interim. Makes the redemption queue painless without the issuer ever fronting a dollar of its own liquidity.

### Scenario 3 — the wallet migration

LP subscribed $500K from a hot wallet, wants it in the family multisig before settlement. One `transferDepositRequest` call, both wallets already KYC-verified, position moves, queue position intact. No money changes hands. Support gets no email. Fee waived or de minimis for same-beneficial-owner transfers.

### Scenario 4 — launch syndication

At vault launch, an anchor desk seeds $5M into the first queue to make the raise look real. Over the following week it transfers $500K–$1M slices to syndicate members as their KYC clears — each at a small premium for having secured queue priority. Fund launches full, anchor earns the placement spread, late investors still get day-one pricing.

---

## Guardrails baked into the reference implementation

1. **KYC/eligibility gate applies to transfers.** The vault's `_update` hook enforces `eligibilityRegistry.eligibleFor(receiver, requiredClaims)` on any share transfer. `newController` in an 8161 transfer holds a *pending* balance (not shares yet), so the mixin does not re-run the check by default — production deployments should override `_beforeTransferDepositRequest` / `_beforeTransferRedeemRequest` to enforce it. Otherwise 8161 becomes a compliance bypass. **This is not optional.**
2. **Operator re-approval before transfer authority activates.** The spec explicitly warns that any operator previously approved on a plain 7540 vault would silently gain new authority to move pending positions. The paranoid answer is right: require each controller to re-approve operators post-8161-upgrade before transfer succeeds. This reference vault leaves that policy to the deployer — production integrators SHOULD add a `transferAuthorityApproved` mapping and gate operator transfers on it.
3. **No canonical price for pending positions.** The spec calls this out. `convertToAssets` does not apply until settlement. Do not build an order book on day one; let transfers settle at whatever price the two parties negotiate off-chain, with the chain recording only the handoff.
4. **Full-balance transfers only.** Per spec — no partial transfers. Callers that need partial semantics should cancel and re-request (accepting the queue-priority cost).
5. **Fee cap.** The reference implementation hard-caps `transferFeeBps` at 100 bps (1%) via `FeeTooHigh` — too-high fees suppress secondary liquidity and defeat the point of the extension.

---

## Why this exists in the library right now

ERC-8161 was published February 2025 by Cain O'Sullivan and Jeroen Offerijns (@hieronx). **Offerijns is CTO of Centrifuge and co-author of ERC-7540 itself.** The FTH Trading tokenization stack is built to sit on Centrifuge Whitelabel as the issuance layer. Adding 8161 support to the Unykorn library at engagement time reframes the customer relationship into first-mover implementer of the vendor's own next-generation standard.

---

## Composition with the rest of the library

- `PermissionedToken` (IdentityRegistry + ClaimTopicsRegistry) — supply the `IEligibilityCheck` interface for KYC-gated share issuance and pending-transfer eligibility.
- `ProofOfReserveConsumer` — plug in if the vault backs a redemption-facing token that needs reserve-ratio circuit breakers before mint.
- `RWAOracle` — plug in for NAV pricing if the fund admin's fulfillment is driven by an on-chain feed.
- `CCIPBridgedToken` — the vault share is ERC-20-transferable (post-settlement), so it can move cross-chain via CCIP once the receiving chain enforces the same eligibility gate.

---

## What's NOT in this reference

- On-chain NAV oracle wiring — deliberately admin-driven via `fulfillDeposit` / `fulfillRedeem` for clarity. Production should replace with the oracle.
- Off-chain fund administrator integration — the Securitize / transfer-agent handoff sits above the FULFILLER_ROLE.
- Cancel-request semantics — deliberately omitted for reference simplicity. Add if the product allows cancellation before fulfillment.
- Cycle/epoch model — this reference uses the single canonical `REQUEST_ID = 0` pattern. Vaults with per-cycle IDs should override the request-management functions accordingly.
- External audit. Same as the rest of the library. Ship to mainnet only after audit.
