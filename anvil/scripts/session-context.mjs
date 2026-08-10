#!/usr/bin/env node
/**
 * ANVIL session context — SessionStart.
 * Emits additionalContext JSON on stdout: git branch, dirty-file count,
 * and the current ops.receipts chain head, so every session opens with
 * provenance state instead of amnesia. Always exits 0.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

const IS_WIN = process.platform === "win32";

function git(args, cwd) {
  const r = spawnSync("git", args, {
    cwd,
    encoding: "utf8",
    timeout: 5000,
    windowsHide: true,
    shell: IS_WIN
  });
  return r.status === 0 ? (r.stdout || "").trim() : null;
}

function receiptsHead(projectDir) {
  const file = path.join(projectDir, ".anvil", "ops.receipts.jsonl");
  if (!existsSync(file) || statSync(file).size === 0) return null;
  const lines = readFileSync(file, "utf8").split("\n").filter((l) => l.trim());
  if (!lines.length) return null;
  try {
    const last = JSON.parse(lines[lines.length - 1]);
    return { count: lines.length, head: String(last.h || "").slice(0, 16), lastTs: last.ts || null };
  } catch {
    return { count: lines.length, head: "unparseable", lastTs: null };
  }
}

function main() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const parts = [];

  const branch = git(["branch", "--show-current"], projectDir);
  if (branch) {
    const dirty = git(["status", "--porcelain"], projectDir);
    const dirtyCount = dirty ? dirty.split("\n").filter((l) => l.trim()).length : 0;
    parts.push(`git: branch=${branch}, uncommitted=${dirtyCount}`);
  }

  const head = receiptsHead(projectDir);
  if (head) {
    parts.push(`ops.receipts: ${head.count} entries, head=${head.head}…, last=${head.lastTs}`);
  } else {
    parts.push("ops.receipts: empty (first receipt will anchor the chain)");
  }

  parts.push(
    "ANVIL active: secrets/destructive-command guards on; lint/typecheck feedback on; " +
    "every Write/Edit/Bash is receipted. On-chain broadcasts and force-pushes are operator-only."
  );

  process.stdout.write(JSON.stringify({ additionalContext: "[ANVIL] " + parts.join(" | ") }));
  process.exit(0);
}

main();
