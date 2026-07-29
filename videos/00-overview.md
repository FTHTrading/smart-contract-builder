# 00 · Overview: what this library is and isn't — 4 min

**Prep:** the catalog site open at `docs/index.html`, scrolled to the top.

## Cold open (0:00 – 0:15)

> "This isn't a token generator. It's the substrate underneath a token generator. And in the audit trail sitting in front of a lender, that difference is the whole product."

*Screen: repo README top, with the "Real Solidity for real-world-asset workflows" tagline highlighted.*

## Slide 1 — What this is (0:15 – 1:00)

> "Smart Contract Builder is a Foundry project with real Solidity for six real-world-asset workflows. Construction draw escrow, permissioned securities, REIT distribution, CMBS tranche waterfalls, SREC tokens, Chainlink oracles. Every contract compiles clean under Solidity 0.8.24 with OpenZeppelin v5 and Anvil paris EVM. Nothing is a snippet."

*Screen: scroll through the catalog site's "The catalog" table, hovering over each row's bytecode size and dependencies columns.*

## Slide 2 — What this is not (1:00 – 1:45)

> "Not a token wizard. If you want a copy-paste ERC-20, use OpenZeppelin's Wizard — it's better at that. Not a legal opinion. Every contract that touches a regulated instrument is clearly labeled as evidence, not the instrument itself. And not audited — no external security audit has been performed on this repo. Every contract here is the starting point for an audit, not the endpoint."

*Screen: hover over the yellow "Legal" callout boxes on Draw Escrow and SREC Token. Then scroll to the "Audit posture" section at the bottom.*

## Slide 3 — Why it exists (1:45 – 2:45)

> "This library is the substrate. The product is Unykorn Studio — the console that drives these contracts through an approval-per-step executor and writes a SHA-256 hash-chained receipt for every state transition. But you can't demonstrate a substrate without real contracts to run through it. So the library exists."

> "The claim is specific and defensible. Studio produces a single cryptographically-linked chain from 'the operator asked for this' through 'this exact bytecode was compiled from these exact sources' through 'it deployed with these exact deal terms' through 'this draw released against this waiver.' No other stack in the counterparty's world produces that artifact end-to-end."

*Screen: switch to Studio at localhost:3200. Click a template, show the Agent Lane steps appear. Then switch to the Receipts tab and show the ledger.*

## Slide 4 — How the pieces fit (2:45 – 3:30)

> "Three repos work together. This one — Smart Contract Builder — is the Solidity. Unykorn Studio is the console. Unykorn Carbon is a portfolio-accounting engine that Studio calls via subprocess for the Carbon Portfolio Assessment capability. Everything else — draw escrow, permissioned securities, REIT, CMBS, SREC, Chainlink — is native Studio templates against contracts from this library."

*Screen: three-panel diagram: [Smart Contract Builder] → [Unykorn Studio] ← [Unykorn Carbon]. Show the arrows going into Studio.*

## Close (3:30 – 4:00)

> "Every contract has a URL. Every URL has a color that tells you the category. Every family in the catalog has bytecode sizes and legal caveats stated up front. If you want to go deeper on any one, the next four videos each cover one family end to end. If you want to skip straight to running it, the README's build-and-test section gets you there in one paste."

*Screen: back to the catalog site, showing the color-coded left sidebar. Cursor hovers over the "Draw Escrow" link.*

**End card:** "smart-contract-builder — v0.5 — fthtrading.github.io/smart-contract-builder"
