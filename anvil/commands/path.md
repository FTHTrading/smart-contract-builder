---
description: Put a project on the ANVIL PATH — initialize a new project's gate file, or retrofit-audit an existing repo against the path
argument-hint: <new|retrofit> <class: custody-chain|trading-rail|ai-agent|web-portal> [project name]
---

Mode and class: $ARGUMENTS

## Mode: new

1. Copy `${CLAUDE_PLUGIN_ROOT}/templates/ANVIL-PATH.md` to `docs/ANVIL-PATH.md` in the project root. Fill in project name, class, date; set Status to G0. Delete every overlay except the selected class. If the class is ambiguous from the project, ask the operator — do not guess a custody project into a web overlay.
2. Create `docs/INTENT.md` as a skeleton with the four G0 headings (thesis, counterparty map, kill criteria, regulatory posture) and stop. G0 content is operator judgment; draft it only from what the operator has actually said, and mark every unfilled item as OPEN.
3. Record path adoption: run `node "${CLAUDE_PLUGIN_ROOT}/scripts/receipt.mjs" --gate PATH-INIT --note "class=<class> project=<name>"`.

## Mode: retrofit (the audit — run this in every existing repo)

1. Copy the template to `docs/ANVIL-PATH.md` as in `new`, select the class, set Status to the honest current stage.
2. Audit the repo against every gate G0→G6 in order. For each checklist item, verify with evidence — read the actual files, run the actual test suite, grep the actual history. Never mark an item done from plausibility.
3. Write `docs/PATH-GAP.md`:
   - Per gate: PASS / PARTIAL / FAIL with one line of evidence per item (file path, command output, or "absent").
   - **The honest gate**: the highest gate this project has actually passed, which is usually lower than where the project believes it is. A deployed system with no runbook and no reconciliation is at G3, whatever is running in production.
   - Gap list ordered by risk, not effort: custody/compliance/money-math gaps first, cosmetic last.
   - For each gap: the exact fix, estimated size (S/M/L), and whether it blocks the next gate.
4. Record the audit: `node "${CLAUDE_PLUGIN_ROOT}/scripts/receipt.mjs" --gate RETROFIT-AUDIT --note "honest_gate=G<n> criticals=<count>"`.
5. Present to the operator: honest gate, top 5 gaps with fixes, and the single next action. Do not start fixing anything until the operator picks.

## Both modes

Status line in `docs/ANVIL-PATH.md` is only ever advanced by `/anvil:gate`, never edited directly.
