# 01 · Draw Escrow: the M Helen use case — 7 min

**Prep:**
- Anvil running: `anvil --host 127.0.0.1 --port 8545 --chain-id 31337`
- Studio running: `pnpm dev` in `dev/platforms/unykorn-studio/`
- Ledger reset via `pnpm demo:reset`
- Terminal open, ready for the tamper beat at the end
- Ops URL bookmarked: `http://localhost:3200/ops/0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0`

## Cold open (0:00 – 0:20)

> "Here's a construction draw that traditionally takes three to ten business days between an inspector's site visit and the money moving. Watch it settle in one block, with a cryptographic receipt that a lender's counsel can independently verify."

*Screen: split view — a stock photo of a construction site on the left, the ops view on the right, no context yet.*

## Slide 1 — The problem (0:20 – 1:15)

> "A construction lender is funding a project — call it M Helen Hotel, an SPV under our client's structure. They advance capital in tranches called draws. Each draw needs three things to be legitimate. One: an inspector confirmed the work was actually done. Two: the general contractor signed a mechanics lien waiver. Three: the amount doesn't exceed what the milestone allows or the retainage math."

> "Traditionally these three signals live in three different places — the inspector's PDF, the waiver in the title company's file, and a spreadsheet at the lender. Reconciling them for one draw is a 3-to-10 day process. And the audit trail is email and paper. If someone disputes a release three years later, the paper trail is what defends it."

*Screen: three PDFs and a spreadsheet, arranged messily. Draw a red line between them showing the reconciliation problem.*

## Slide 2 — What the contract does (1:15 – 2:30)

> "The DrawEscrow contract collapses that three-place reconciliation into one on-chain transaction. The inspector attests on-chain to the MilestoneRegistry — that's tx one, done at the site visit. The waiver document is signed off-chain — actual paper, statutory form, exactly as Georgia law requires under O.C.G.A. section 44-14-366 — and its keccak256 hash gets committed on-chain. That's the crypto proof that the waiver document is what everyone agreed it was."

> "When it's time to release, the lender calls releaseDraw with the milestone, the amount, the waiver, and the attestor's signature. The contract checks four things — the milestone is attested at or above this amount, the waiver hash is signed by the correct attestor address, the draw number is the next one in sequence for replay protection, and there are enough funds after retainage. All four pass, funds move in one transaction."

*Screen: DrawEscrow.sol open in an editor, cursor on the releaseDraw function. Highlight the four check lines.*

## Slide 3 — Live demo: process a draw (2:30 – 4:30)

> "Let me actually do this."

*Screen: switch to the ops view. Cursor hovers over the escrow's Process Draw button on milestone 1.*

> "Milestone one is already attested — the inspector posted their attestation during demo reset. I click Process Draw. Modal opens with four stages."

*Screen: click through. Upload a PDF — pick any file, even a text file, for the demo.*

> "Stage one: upload the waiver PDF. The moment I select the file, the browser computes both a keccak256 hash — that's what the contract will check against — and a SHA-256 hash for the ledger. The PDF bytes never leave my machine. The ledger records that a waiver was committed, with both hashes, filename, byte length. It does not record the file."

*Screen: hashes visible in the modal. Point at the "PDF bytes never transmitted" green line.*

> "Stage two: draw amount and waiver through-amount. Then this button — cross-check EIP-712 digest. This calls the contract's hashWaiver view function and compares the digest to what my browser computed via viem. If they don't match, signing does not proceed. This is the single fail-fast gate that turns a two-hour debugging session into a one-line client error."

*Screen: click cross-check. Green checkmark appears.*

> "Stage three: the attestor signs. In production this hands the payload to a title company employee's wallet — MetaMask, hardware, or BitGo Enterprise via sign_external. For the demo it's an Anvil account. Signature captured."

*Screen: click through sign. Show the signature preview.*

> "Stage four: submit the release. Lender wallet sends the transaction. Contract checks pass. Ninety-thousand LTT to the GC, ten-thousand held as retainage, tx confirmed."

*Screen: green confirmation. Point at the tx hash and block number.*

## Slide 4 — The audit trail (4:30 – 5:45)

> "Now here's the part counsel cares about. Switch back to Studio. Bottom tab: Receipts."

*Screen: click Receipts tab. Show the growing ledger.*

> "Every step wrote a receipt. Waiver committed — dual hash, no PDF bytes. Attestation received — signer, digest, signature. Draw released — transaction hash, block, amounts. All three chain-linked to each other and back to the compile receipt that produced the DrawEscrow bytecode and the deploy receipt that put it on-chain."

*Screen: click each receipt, show the payload.*

> "Counsel can walk this backwards. Address of the escrow they're evaluating. The deploy receipt records what compile it came from. The compile receipt records the inputHash — SHA-256 of the full compilation input — and the hash of the solc binary itself, verified against binaries.soliditylang.org. Given only those two hashes and the pinned Solidity 0.8.24 binary, counsel can independently reproduce every byte of the deployed bytecode."

*Screen: split view — receipts panel on left, catalog site on right showing the audit section.*

## Slide 5 — Attestor rotation (5:45 – 6:30)

> "One thing the memory failure at Zoth in March 2025 taught the market. If the attestor's private key is compromised, you need a rotation path. But that path can NOT be an unrestricted admin setter — that's exactly how Zoth lost eight million dollars. Someone got the admin key and immediately rotated the signer to their own address."

> "So the DrawEscrow ships with a two-step timelocked rotation. Lender proposes a new attestor — visible immediately in the ops view as an amber banner. Timelock elapses — configurable per deployment, 24 hours in the demo. Lender executes. Old attestor's signature no longer verifies. Lender can cancel any time before execution. Every stage writes a receipt."

*Screen: run through proposeAttestorRotation → wait indicator → executeAttestorRotation. Show the amber pending banner in ops view.*

## Close (6:30 – 7:00)

> "Draw escrow — one contract family, four Solidity files, real deployment against a real chain in the smart-contract-builder repo. Studio integration ships in the unykorn-studio repo. And the audit trail sitting behind the ops view is the same shape for every other capability in the library — permissioned securities, REIT, CMBS, SREC, oracles, carbon."

> "Next video walks through permissioned securities — ERC-3643 without the full T-REX complexity."

*Screen: back to catalog site, cursor on Permissioned Security Token link.*

**End card:** "smart-contract-builder — 01 draw escrow — next: permissioned securities"
