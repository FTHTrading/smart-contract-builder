---
description: Attempt to pass an ANVIL PATH gate — verifies exit criteria with evidence, refuses out-of-order passage, records the gate into the receipts chain
argument-hint: <G0..G7>
---

Gate under review: $ARGUMENTS

1. Read `docs/ANVIL-PATH.md`. If absent, stop: "no path — run /anvil:path first."
2. **Order check**: the requested gate must be exactly Status+1 (G7 repeats and may be run any time at/after G6). Skipping is refused outright — if the operator wants to skip, they say so explicitly, and the skip itself is receipted as `--gate G<n>-WAIVED` with their reason verbatim. A waiver is a recorded decision, not a silent pass.
3. **Verify every exit criterion** for the gate, including the class overlay additions, with hard evidence:
   - File-existence items: read the file, confirm it has real content, not a heading skeleton.
   - Test items: run the suite now; paste the summary line.
   - "Rehearsed/executed once" items (rollback drill, key-rotation drill): require the receipt or log of that execution; a claim without an artifact is FAIL.
   - Sign-off items (legal, external audit, operator waiver): require the operator to state it in this conversation; record their words in the gate note.
4. Verdict:
   - **All pass** → check the boxes in `docs/ANVIL-PATH.md`, advance the Status line, and record:
     `node "${CLAUDE_PLUGIN_ROOT}/scripts/receipt.mjs" --gate G<n> --note "<one-line evidence summary>"`
   - **Any fail** → do not touch the Status line. Output the failing items with the exact remediation for each, sized S/M/L, and stop. A failed gate attempt is normal operation, not a problem to soften.
5. Never combine gates in one pass, and never let "we're launching Friday" compress verification — schedule pressure is exactly when G4/G5 skips create the incidents this path exists to prevent. If the deadline genuinely dominates, that's the operator's waiver call under step 2, on the record.
