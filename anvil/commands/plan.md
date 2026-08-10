---
description: Turn an approved spec into an ordered TDD execution plan (ANVIL discipline, replaces superpowers planning)
argument-hint: <spec file path, or feature name if the spec is in specs/>
---

Build an execution plan from the spec: $ARGUMENTS

1. Load the spec file. If no spec exists, stop and tell the operator to run `/anvil:spec` first — plans without specs are how scope drifts.
2. Write the plan to `specs/<name>.plan.md` as an ordered list of steps where every step is one red-green-refactor cycle:
   - **Step N** — the single failing test to write, the minimal code to pass it, the files touched.
   - Each step must be independently committable with all tests green at the end of it.
   - Order steps so custody/compliance invariant tests land before feature convenience.
3. Mark any step that requires operator action (on-chain broadcast, force push, secret provisioning, third-party account) with `⛔ OPERATOR GATE` — those steps are proposed, never executed.
4. Estimate blast radius per step: which existing tests could break, which modules are load-bearing.
5. Present the plan summary in chat: step count, gate count, first three steps. Then execute step 1 only — write the failing test, run it, confirm it fails for the right reason — and stop for confirmation before the first green.
6. During execution, after each step: run the full relevant test suite, then update the plan file marking the step `✅ <commit-worthy summary>`. The plan file is the progress ledger; never hold progress only in conversation.
