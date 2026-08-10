---
description: Write a build spec for a feature before any code is written (ANVIL discipline, replaces claudekit /spec)
argument-hint: <feature or change to spec>
---

Produce a build spec for: $ARGUMENTS

Rules of this command — no code is written during /spec:

1. Read the relevant existing code first. Cite exact file paths and line references for every claim about current behavior. Never assert what the codebase does from memory.
2. Write the spec to `specs/<kebab-case-name>.md` in the project root with exactly these sections:
   - **Objective** — one paragraph, outcome-framed, with the money/operational reason this exists.
   - **Current state** — what exists today, with file:line citations.
   - **Design** — data structures, interfaces, and control flow. Integer minor units for all money values. No floats in financial paths.
   - **Invariants** — properties that must hold before and after (custody boundaries, compliance gates before value movement, append-only logs). Each invariant maps to a test in the next section.
   - **Test plan** — the failing tests to write first, named, one per invariant plus edge cases.
   - **Out of scope** — explicit non-goals so the implementation doesn't sprawl.
   - **Open questions** — anything requiring an operator decision, framed as Option A / Option B with the trade-off stated.
3. If the change touches value movement, custody, key material, or deployment, add a **Gates** section listing the human-approval gates and where they sit in the flow.
4. End by presenting the Open questions to the operator and stopping. Do not begin implementation until the operator answers or says "proceed".
