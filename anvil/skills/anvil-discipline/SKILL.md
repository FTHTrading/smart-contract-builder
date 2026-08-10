---
name: anvil-discipline
description: Unykorn ANVIL engineering discipline. Use for ANY implementation work in Unykorn repositories — writing code, fixing bugs, refactoring, deploying, or touching contracts, custody, payment rails, or infrastructure. Trigger on "build", "implement", "fix", "refactor", "deploy", "ship", or when starting work in a repo containing .anvil/, specs/, or an ANVIL.md. Enforces spec-before-code, test-first, integer money math, operator gates on value movement, and receipted changes.
---

# ANVIL Discipline

The operating rules for all engineering work in Unykorn repositories. The hooks enforce the hard boundaries mechanically; this skill governs judgment.

## The Path

Every project — stablecoin, custody integration, trading rail, XRPL build, AI agent, portal — lives on the ANVIL PATH: gates G0 (intent/kill criteria) → G1 (spec) → G2 (plan) → G3 (build) → G4 (audit) → G5 (deploy) → G6 (launch) → G7 (operate, weekly). Gate state lives in `docs/ANVIL-PATH.md`; passage is receipted into the chain via `/anvil:gate` and nothing advances without it. If a repo has no `docs/ANVIL-PATH.md`, the first action on any substantive request is to say so and offer `/anvil:path retrofit` — then continue with the requested work; the path is mandatory, but it never becomes an excuse to stall the operator's task. Class overlays (custody-chain, trading-rail, ai-agent, web-portal) add the domain-specific audit and launch requirements; the overlay is part of the gate, not optional flavor.

## Work order

1. **Spec before code.** Non-trivial changes get `/anvil:spec` first. Trivial = one file, no invariant touched, reversible in one commit. Everything else gets a spec with cited current-state.
2. **Plan before implementation.** `/anvil:plan` converts the spec to ordered red-green-refactor steps. Execute steps in order; each ends with all tests green and the plan file updated.
3. **Review before commit.** `/anvil:review` on the actual diff. Critical/High findings are fixed before commit, not filed.

## Hard rules (also enforced by hooks — do not attempt to route around them)

- **Never read or write secret material.** `.env*`, keys, keystores, wallets, mnemonics, SSH material. If a secret's value is needed, ask the operator; reference `process.env`/config indirection in code.
- **On-chain writes are operator-only.** `forge --broadcast`, `cast send`, anything against a mainnet RPC: produce the exact command as text for the operator to run. Same for force-pushes to protected branches, SQL DROP/TRUNCATE, and recursive deletes of root paths.
- **Money is integers.** Minor units (drops, wei, cents) end to end. Division states its rounding direction and accounts for dust explicitly.
- **Compliance gates before value moves.** KYC/whitelist/sanction checks evaluate before, and atomically with, any transfer, mint, or distribution. Never after, never optimistically.
- **Logs are append-only.** `ops.receipts` files and any audit ledger are never edited, reordered, or rewritten. Corrections are new entries referencing the corrected one.
- **Determinism in consensus paths.** No floats, no wall-clock, no unseeded randomness, no map-order dependence in L1 state transitions, Hooks, or anything that must replay.

## Evidence standard

Claims about current code cite file:line. Claims about external behavior cite the doc or the test that proved it. "It should work" is not a state; green tests are a state.

## Failure posture

When a hook blocks an action, that block is correct by default. State what was blocked and why, propose the operator-side alternative, and continue with what remains executable. Never suggest `ANVIL_OVERRIDE` unprompted.
