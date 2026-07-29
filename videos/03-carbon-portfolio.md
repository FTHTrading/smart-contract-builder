# 03 · Carbon Portfolio: subprocess bridge as abstraction test — 5 min

**Prep:**
- Studio running
- Carbon engine at `dev/finance/unykorn-carbon/` present
- Studio home page open, ready to click the Carbon Portfolio template

## Cold open (0:00 – 0:20)

> "Every capability we've shown so far compiles Solidity and deploys it. This one does neither. It runs a Node subprocess against a portfolio-accounting engine that lives in a different repo, produces a footprint number, and writes it into the same hash-chained ledger. If the abstraction is real, this should just work without changing anything about Studio."

*Screen: catalog site → Carbon Portfolio Assessment section. Point at the "engine subprocess bridge" line in the table.*

## Slide 1 — The setup (0:20 – 1:10)

> "UnyKorn Carbon is a TypeScript engine that computes Scope 1, 2, and 3 emissions for a portfolio of entities. EPA eGRID 2023 factors for electricity by grid subregion. GHG Emission Factors Hub constants for natural gas and fuels. DEFRA 2024 for aviation. Cornell benchmarking index for hotels. Every constant has a source."

> "The engine ships five CLI commands and one JSON emitter that spits out the full portfolio result on stdout — breakdowns per entity, SREC valuation per generation asset, offset recommendations for the net gap, plus a rollup. That JSON is what Studio consumes."

*Screen: run `pnpm --prefix ../../../finance/unykorn-carbon calc` in a terminal. Show the CLI output. Then run the JSON emitter to show the structured output.*

## Slide 2 — The Studio integration (1:10 – 2:00)

> "Studio's carbon capability has five steps. Calculate emissions — this is the one that calls the engine. Value SRECs, recommend offsets, write report — each reads from the calc's cached snapshot. Then a note step for the ops-view handoff. And a sixth unwired branch for on-chain retirement, which requires integration with Toucan or Puro."

*Screen: switch to Studio. Click the Carbon Portfolio Assessment template. Agent Lane fills with the 6 steps.*

> "Approve calc:emissions. The handler makes a fetch to /api/carbon/portfolio — a server route that spawns the engine as a subprocess and returns the parsed JSON. Result comes back in about a hundred milliseconds. Receipt written with the full per-entity breakdown."

*Screen: click approve. Watch the terminal show `> emissions: 6 entities · gross 2064.87t · schema v1`. Click the emissions_calculated receipt.*

## Slide 3 — Why this matters for the platform thesis (2:00 – 3:30)

> "Adding this capability required zero changes to Studio's executor dispatch loop. Zero changes to the ledger's hash chain math. Zero changes to the gate policy mechanics. Only additions at the declared extension points — five new step kinds, six new receipt actions, two new IRREVERSIBLE entries, six capability entries, six template entries."

*Screen: catalog site's "abstraction test" section. Read the changes list.*

> "That's what proves this is a platform, not a demo. The first capability was construction draw escrow. This one is carbon accounting. They are structurally as different as two capabilities can be — draw escrow is a Solidity contract lifecycle, carbon is a subprocess call to a Node engine — and they run on the same substrate without modification."

> "If the abstraction had failed here, that would be the moment to redesign the substrate. It didn't. So next capabilities — ERC-3643 permissioned issuance was capability two-through-six, and the on-chain retirement layer is queued as the seventh — go on the same rails."

*Screen: back to Studio, click through the remaining carbon steps. Watch receipts fill in. All hash-linked.*

## Slide 4 — What lands in the audit trail (3:30 – 4:20)

*Screen: Receipts tab, filtered to the carbon run.*

> "One llm_proposed receipt if the LLM was asked to refine the ask. One emissions_calculated with the full portfolio snapshot. One srecs_valued with voluntary and compliance uplift. One offsets_recommended with the per-entity offset portfolio and cost band. One report_written with the summary. Every one chain-linked to the previous, every one derived from a single engine call — which means an auditor can independently verify the number by running the same engine against the same data."

> "The receipt does NOT store the raw ask. It stores a SHA-256 of the ask. Because in a real portfolio the ask might name specific SPVs, dollar amounts, or counterparty entities that don't belong in an ESG report shared externally."

## Close (4:20 – 5:00)

> "One capability. Zero changes to Studio's core. That's the platform thesis proven in about forty lines of TypeScript for the adapter and one JSON emitter script for the engine side. Every subsequent capability slots in the same way."

> "Next and last video — three minutes on the tamper beat. The single most important demonstration in front of counsel."

**End card:** "smart-contract-builder — 03 carbon portfolio — next: the tamper beat"
