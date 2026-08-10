---
description: Verify and summarize the hash-chained ops.receipts audit log for this project
allowed-tools: Bash(node *), Read
---

Verify the ANVIL receipts chain, then summarize it.

1. Run: `node "${CLAUDE_PLUGIN_ROOT}/scripts/receipt.mjs" --verify`
   - If the chain verifies, report the entry count and head hash.
   - If the chain is broken, report the exact line number and both hashes, and state plainly that the log was tampered with or corrupted after that line — do not soften it. Recommend preserving the file as-is and starting a fresh chain file rather than editing history.
2. Read `.anvil/ops.receipts.jsonl` and summarize the session: distinct sessions, files touched (by path), bash commands executed (by head), time span, and any entries carrying `override: true` — call those out explicitly, since they mark guard-disabled activity.
3. Do not modify the receipts file under any circumstances. It is append-only by design; this command is read-only.
