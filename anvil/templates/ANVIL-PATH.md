# ANVIL PATH — <PROJECT NAME>

Class: <custody-chain | trading-rail | ai-agent | web-portal>
Owner: Kevan Burns (operator; sole gate authority)
Started: <date>
Status: G<current>

Rule zero: **no work in stage N+1 until gate GN carries a receipt** (`/anvil:gate GN`).
Gate passage is recorded in `.anvil/ops.receipts.jsonl` — the chain is the project's provenance, from intent to operation. A project with no gate receipts is, by definition, not launched.

---

## G0 — INTENT (kill it here or fund it here)

Exit criteria — all checked, evidence linked:
- [ ] One-page thesis in `docs/INTENT.md`: what it earns, who pays, first-dollar date, and the number that makes it worth doing.
- [ ] Counterparty/dependency map: every external party (custodian, venue, chain, API, regulator) and what breaks if they say no.
- [ ] Kill criteria written down: the measurable conditions under which this project dies. (Inventory rule: every asset makes money or gets killed — the kill line is defined *before* the build.)
- [ ] Regulatory posture: one paragraph — money transmission? securities? custody? Which existing entity/license covers it, or what's the gap.
- [ ] Named class overlay selected (below) and irrelevant overlays deleted from this file.

## G1 — SPEC

- [ ] `/anvil:spec` run; `specs/<name>.md` exists with cited current-state, invariants, and test plan.
- [ ] Threat model section: who attacks this, what they steal, top 5 abuse paths.
- [ ] Every invariant maps to a named test.
- [ ] Open questions answered by operator (recorded in the spec, not in chat).

## G2 — PLAN

- [ ] `/anvil:plan` run; `specs/<name>.plan.md` exists — ordered red-green-refactor steps, each independently committable.
- [ ] Every ⛔ OPERATOR GATE step identified (broadcasts, secrets, third-party accounts).
- [ ] Definition of done for the build stage: which tests, what coverage of invariants, what performance bar.

## G3 — BUILD

- [ ] All plan steps ✅ in the plan file; full test suite green.
- [ ] Every invariant test exists and fails when the invariant is broken (mutation-check at least the custody/money ones by hand).
- [ ] No floats in money paths; integer minor units end to end; rounding direction documented at each division.
- [ ] Zero `TODO`/`FIXME`/commented-out code in shipped paths.
- [ ] Repo hygiene: `.anvil/` receipts committed policy decided, secrets absent from history (`git log -p` spot check), lockfiles committed.

## G4 — AUDIT

- [ ] `/anvil:review` run on the full diff since G2; zero Critical/High open.
- [ ] Class-specific audit complete (see overlay).
- [ ] Dependency review: licenses of everything shipped, pinned versions, no `curl | sh` installs anywhere in setup docs.
- [ ] Failure-mode table in `docs/FAILURE-MODES.md`: for each dependency down / input malformed / partial write — what state results, how it's detected, how it's recovered.
- [ ] Second set of eyes: external audit engaged if the overlay requires it, or explicit operator waiver recorded in the gate note.

## G5 — DEPLOY

- [ ] Reproducible build: build inputs hashed, artifact hash recorded; runtime-matches-build check where applicable.
- [ ] Deploy receipt written (chain instance/genesis hash for on-chain; image digest + config hash for services).
- [ ] Rollback rehearsed, not just written: the rollback command was actually executed against staging once.
- [ ] Secrets provisioned by operator only; app reads env/keychain; nothing in repo or logs.
- [ ] All on-chain broadcasts and production pushes executed by operator, receipted.

## G6 — LAUNCH

- [ ] `docs/RUNBOOK.md`: start/stop, health checks, top 5 incidents with exact commands, escalation (who gets called, in what order).
- [ ] Monitoring live before users: liveness, error rate, and the one business metric from G0, with alerts that reach a phone.
- [ ] Partner-facing artifact exists: the walkthrough/demo a counterparty's diligence team sees (fund flows, audit trail, receipts chain).
- [ ] Legal/compliance sign-off for the class (see overlay) recorded in the gate note.
- [ ] Support path: where a user/partner reports a problem and the SLA on first response.
- [ ] Launch announcement/GTM asset shipped or explicitly deferred with a date.

## G7 — OPERATE (recurring, weekly)

- [ ] `/anvil:receipts` chain verifies; any `override: true` entries explained.
- [ ] Business metric vs. G0 thesis reviewed; kill criteria evaluated honestly.
- [ ] Incident log reviewed; every incident produced either a fix or a runbook entry.
- [ ] Dependency/CVE sweep on pinned versions.

---

# CLASS OVERLAYS — keep one, delete the rest

## Overlay: custody-chain (stablecoins, BitGo Express, XRPL Hooks/MPTs, ERC-3643, vaults)

Adds to G1: custody boundary diagram — for every key, who holds it, m-of-n, where the user-held backup key lives; explicit statement of why Unykorn is never sole custodian and never balance-sheet liable.
Adds to G4: full smart-contract security audit pass (reentrancy, access control, oracle, ordering); Hooks guard/state/reserve/rollback review for XRPL; compliance-gate placement check — KYC/whitelist/sanctions evaluated before and atomically with every value movement; testnet soak with adversarial txns.
Adds to G5: broadcast checklist — chainId + genesis/network verified, constructor args cross-checked against deal terms, contract verification published; operator signs, never the agent.
Adds to G6: Travel Rule / AML procedure documented for flows over threshold; incident path for a compromised key (rotation drill executed once on testnet); licensed external audit before high-value mainnet, or written operator waiver with value cap.

## Overlay: trading-rail (FalconX, Osprey, OTC/settlement, neobank/MSB flows)

Adds to G1: settlement diagram — every leg, who bears counterparty risk during the window, netting rules; fee schedule and who Unykorn invoices.
Adds to G4: reconciliation is a build requirement, not an ops afterthought — automated match of venue statements vs. internal ledger vs. bank/chain, with a break-report; idempotency on every order/transfer submission; replay/duplicate-fill handling tested.
Adds to G5: sandbox → limits-capped production progression with explicit per-day notional caps raised only by operator gate note.
Adds to G6: counterparty onboarding docs pack (entity, licenses, insurance, SOC/audit letters) collected before first dollar; daily reconciliation report wired to operator.

## Overlay: ai-agent (Finn, Hearth, swarm services)

Adds to G1: authority boundary — exact list of tools/actions the agent can take autonomously vs. operator-gated; data-sensitivity routing (private data local-only per provider policy).
Adds to G4: prompt-injection and ingestion-guard review (malicious documents, nested archives, filter coverage); tool-call guardrails equivalent to the anvil hooks in whatever runtime the agent uses; eval set — a fixed battery of tasks with pass criteria, run before every model/prompt change; memory/logs contain no secrets.
Adds to G5: model+prompt version pinning; every agent action logged append-only with inputs hash.
Adds to G6: human-approval gates demonstrated live in the partner walkthrough; degradation behavior defined (provider down → fallback chain → safe halt, never silent wrong answers).

## Overlay: web-portal (portals, sites, dashboards, partner apps)

Adds to G4: authn/authz review per route; tenant isolation tested with a hostile-tenant test; OWASP top-10 pass; no client-side secrets.
Adds to G5: preview → production promotion with immutable deploy IDs; DNS/TLS verified; Lighthouse/CWV floor met.
Adds to G6: uptime monitoring + status path; brand pass against the Unykorn brand system; analytics on the one metric that matters.
