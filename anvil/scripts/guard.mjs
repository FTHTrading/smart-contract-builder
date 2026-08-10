#!/usr/bin/env node
/**
 * ANVIL guard — PreToolUse.
 * Mode "file": blocks Read/Edit/Write/MultiEdit against secret material.
 * Mode "bash": blocks destructive or custody-endangering shell commands.
 *
 * Protocol: exit 0 = allow, exit 2 = block (stderr is fed back to Claude).
 * Fail-open on malformed input so a broken hook never bricks the session,
 * but every block and every fail-open is written to stderr for the operator.
 *
 * Escape hatch (deliberate, operator-only): set ANVIL_OVERRIDE=1 in the
 * environment of the `claude` process to disable guards for that session.
 * The override itself is logged by receipt.mjs via the session env marker.
 */

import { readFileSync } from "node:fs";
import path from "node:path";

const mode = process.argv[2] || "file";

function readStdin() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return null;
  }
}

const SECRET_FILE_PATTERNS = [
  /(^|[\\/])\.env(\.[A-Za-z0-9._-]+)?$/i,
  /(^|[\\/])secrets?\.env$/i,
  /(^|[\\/])\.finn[\\/]secrets\.env$/i,
  /\.pem$/i,
  /\.key$/i,
  /\.p12$/i,
  /\.pfx$/i,
  /(^|[\\/])id_(rsa|ed25519|ecdsa)(\.pub)?$/i,
  /(^|[\\/])keystore([\\/]|\.json$)/i,
  /(^|[\\/])wallet\.json$/i,
  /(^|[\\/])\.aws[\\/]credentials$/i,
  /(^|[\\/])\.ssh[\\/]/i,
  /(^|[\\/])\.npmrc$/i,
  /(^|[\\/])\.netrc$/i,
  /mnemonic|seed[-_.]?phrase/i
];

const DESTRUCTIVE_BASH_PATTERNS = [
  // filesystem nukes
  { re: /\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\b\s+(\/|~|\$HOME|[A-Za-z]:\\)\s*$/m, why: "recursive force-delete of a root path" },
  { re: /\brm\s+-rf?\s+\*(\s|$)/, why: "rm -rf * (unscoped wipe)" },
  { re: /\bmkfs\.|\bdd\s+if=.*of=\/dev\//, why: "raw device write" },
  // git history / remote destruction
  { re: /git\s+push\s+[^\n]*(--force|-f)\b[^\n]*\b(main|master|production|release)\b/, why: "force push to a protected branch" },
  { re: /git\s+push\s+[^\n]*\b(main|master|production|release)\b[^\n]*(--force|-f)\b/, why: "force push to a protected branch" },
  { re: /git\s+reset\s+--hard\s+[^\n]*&&[^\n]*git\s+push\s+[^\n]*(-f|--force)/, why: "hard reset + force push" },
  { re: /git\s+branch\s+-D\s+(main|master)\b/, why: "deleting a protected branch" },
  // database destruction
  { re: /\bDROP\s+(TABLE|DATABASE|SCHEMA)\b/i, why: "SQL DROP statement in shell" },
  { re: /\bTRUNCATE\s+TABLE\b/i, why: "SQL TRUNCATE in shell" },
  // curl | sh supply-chain installs
  { re: /(curl|wget|iwr|Invoke-WebRequest)[^\n|;]*\|\s*(ba)?sh\b/i, why: "piping a remote script into a shell" },
  { re: /(curl|wget)[^\n|;]*\|\s*sudo\b/i, why: "piping a remote script into sudo" },
  // chain custody: broadcast / mainnet actions require the operator, not the agent
  { re: /\bforge\s+(script|create)\b[^\n]*--broadcast\b/, why: "forge --broadcast (on-chain write) requires operator execution" },
  { re: /\bcast\s+send\b/, why: "cast send (on-chain write) requires operator execution" },
  { re: /--rpc-url\s+\S*mainnet/i, why: "mainnet RPC in an agent-issued command" },
  // secret exfiltration via shell
  { re: /\b(cat|type|Get-Content|less|more|head|tail)\b[^\n|;&]*(\.env(\.[A-Za-z0-9._-]+)?|secrets?\.env|\.pem|id_rsa|wallet\.json)(\s|$|["'])/i, why: "reading secret material via shell" },
  { re: /\b(printenv|env)\b\s*($|\|)/m, why: "dumping the full process environment" },
  { re: /(curl|wget|iwr)[^\n]*(-d|--data|--data-binary|-F)[^\n]*\$\{?[A-Z_]*(KEY|TOKEN|SECRET|PASS)/i, why: "posting a credential-shaped variable to a remote host" },
  // permission bombs
  { re: /\bchmod\s+(-R\s+)?777\b/, why: "chmod 777" },
  { re: /:\(\)\s*\{\s*:\|\s*:\s*&\s*\}\s*;\s*:/, why: "fork bomb" }
];

function block(message) {
  process.stderr.write(`[ANVIL GUARD] BLOCKED: ${message}\n`);
  process.exit(2);
}

function main() {
  if (process.env.ANVIL_OVERRIDE === "1") process.exit(0);

  const input = readStdin();
  if (!input || typeof input !== "object") {
    process.stderr.write("[ANVIL GUARD] fail-open: unreadable hook input\n");
    process.exit(0);
  }

  const toolInput = input.tool_input || {};

  if (mode === "file") {
    const candidates = [];
    if (typeof toolInput.file_path === "string") candidates.push(toolInput.file_path);
    if (typeof toolInput.notebook_path === "string") candidates.push(toolInput.notebook_path);
    if (Array.isArray(toolInput.edits)) {
      for (const e of toolInput.edits) {
        if (e && typeof e.file_path === "string") candidates.push(e.file_path);
      }
    }
    for (const raw of candidates) {
      const p = path.normalize(raw);
      for (const re of SECRET_FILE_PATTERNS) {
        if (re.test(p)) {
          block(
            `"${p}" matches a secret-material pattern (${re}). ` +
            `Secrets are never read or written by the agent. If a value from this file is needed, ` +
            `ask the operator to export it or reference it indirectly (e.g. process.env at runtime).`
          );
        }
      }
    }
    process.exit(0);
  }

  if (mode === "bash") {
    const cmd = typeof toolInput.command === "string" ? toolInput.command : "";
    if (!cmd) process.exit(0);
    for (const { re, why } of DESTRUCTIVE_BASH_PATTERNS) {
      if (re.test(cmd)) {
        block(
          `command matches destructive pattern — ${why}. ` +
          `Command was: ${cmd.slice(0, 300)}${cmd.length > 300 ? "…" : ""}. ` +
          `Propose the command to the operator in plain text instead of executing it. ` +
          `Operator can run it manually or set ANVIL_OVERRIDE=1 for this session.`
        );
      }
    }
    process.exit(0);
  }

  process.exit(0);
}

main();
