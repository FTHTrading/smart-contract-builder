# ANVIL — Unykorn process plugin for Claude Code

Sovereign replacement for `superpowers` + `claudekit`. Every hook is first-party code in this repo; nothing third-party intercepts tool calls.

## What it does

| Layer | Mechanism | Effect |
|---|---|---|
| Secrets guard | `PreToolUse` on `Read/Edit/Write/MultiEdit` → `scripts/guard.mjs file` | Blocks any agent access to `.env*`, keys, keystores, wallets, mnemonics, SSH material. Exit 2 = hard block. |
| Destructive-command gate | `PreToolUse` on `Bash` → `scripts/guard.mjs bash` | Blocks `rm -rf` on roots, force-push to main/master, SQL DROP/TRUNCATE, `curl \| sh`, `forge --broadcast`, `cast send`, mainnet RPC calls, secret exfil via shell. Blocked commands are proposed to the operator instead. |
| Real-time quality | `PostToolUse` on `Write/Edit/MultiEdit` → `scripts/quality.mjs` | Runs the fastest available checker for the touched file (tsc/eslint, cargo check + fmt, ruff, forge build, JSON parse). Failures exit 2 → error text feeds straight back to Claude for an immediate fix. Missing toolchains pass silently; 20s hard timeout. |
| Receipts | `PostToolUse` on `Write/Edit/MultiEdit/Bash` → `scripts/receipt.mjs` | Appends a hash-chained JSONL entry per mutating call to `<project>/.anvil/ops.receipts.jsonl`. `--verify` walks the chain. |
| Session provenance | `SessionStart` → `scripts/session-context.mjs` | Injects git branch, dirty count, and receipts chain head into every new session. |
| ANVIL PATH | `templates/ANVIL-PATH.md` + `/anvil:path` + `/anvil:gate` | Stage-gated lifecycle G0(intent)→G7(operate) with class overlays (custody-chain, trading-rail, ai-agent, web-portal). `path retrofit` audits an existing repo into an honest-gate + gap report; `gate` verifies exit criteria with evidence and receipts passage into the chain. Skips only by explicit receipted waiver. |
| Workflow | `/anvil:spec`, `/anvil:plan`, `/anvil:review`, `/anvil:receipts` | Spec-before-code, ordered TDD plan, adversarial diff review, chain verification. |
| Judgment | `skills/anvil-discipline` | Integer money math, compliance-before-value-movement, append-only logs, operator gates. |

## Install

Local (no GitHub needed):

```powershell
# from any Claude Code session
/plugin marketplace add C:\Users\Kevan\dev\process\unykorn-anvil
/plugin install anvil@unykorn
```

Or push this repo to `github.com/unykorn/unykorn-anvil` and:

```
/plugin marketplace add unykorn/unykorn-anvil
/plugin install anvil@unykorn
```

Restart the session (or `/reload-plugins`). The `[ANVIL]` line in session context confirms hooks are live.

## Verify it's working

```powershell
# 1) Ask Claude to read a .env file — expect a GUARD block.
# 2) Ask Claude to run `git push --force origin main` — expect a GUARD block.
# 3) Have Claude write a .ts file with a type error — expect immediate tsc feedback.
# 4) Check the chain:
node <plugin-root>/scripts/receipt.mjs --verify
```

## Operator override

`ANVIL_OVERRIDE=1` in the environment of the `claude` process disables guards for that session. Every receipt written during an overridden session carries `override: true`, and `/anvil:receipts` calls those entries out. Use it; don't hide it.

## Design decisions

- **Node-only scripts** (`.mjs`): Claude Code already requires Node, so hooks run identically on Windows/macOS/Linux with zero extra runtime.
- **Fail-open on infrastructure, fail-closed on policy**: unreadable hook input or a crashed checker never bricks the loop; a matched secret path or destructive command always blocks.
- **Receipts never block**: the audit log is best-effort per entry but tamper-evident in aggregate — any post-hoc edit breaks the chain at that line.
