---
description: Adversarial self-review of the current diff before commit (ANVIL discipline)
argument-hint: [optional scope, defaults to uncommitted changes]
---

Review the current changes: $ARGUMENTS

Run `git diff` (and `git diff --staged`) and review the actual diff — not your memory of what you wrote. Adopt the posture of a hostile auditor who profits from finding a flaw. For each file changed, check in this order:

1. **Custody & value movement** — can any path move value, sign, or broadcast without an explicit gate? Are compliance checks (KYC/whitelist/sanctions) evaluated *before* the transfer, atomically, with no reordering window?
2. **Money math** — any float touching a financial quantity is a finding. Integer minor units only. Check rounding direction on division: who eats the dust, and is it recorded?
3. **Determinism** — wall-clock reads, unseeded randomness, map-iteration-order dependence, or environment-dependent behavior in anything that must replay identically.
4. **Error paths** — every `unwrap`/`expect`/bare `catch`/swallowed promise rejection in the diff. What state is left half-written when it fires?
5. **Injection & inputs** — untrusted input reaching shell, SQL, file paths, or eval-like sinks. Path traversal on any user-supplied filename.
6. **Reentrancy & ordering** (Solidity/Hooks) — external calls before state writes, missing checks-effects-interactions, guard/state pitfalls.
7. **Log integrity** — does anything mutate or rewrite an append-only log instead of appending?
8. **Test honesty** — do the new tests assert the invariant, or just that the code runs? A test that can't fail is a finding.

Output format: findings as a severity-ordered list (Critical / High / Medium / Low), each with file:line, the exact problem, and the exact patch. Zero findings must be stated as "reviewed N files, no findings against checks 1–8" — never silence. If any Critical or High exists, apply the patches, re-run tests, and re-review the patched hunks before declaring done.
