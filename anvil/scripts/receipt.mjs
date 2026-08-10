#!/usr/bin/env node
/**
 * ANVIL receipts — PostToolUse on Write/Edit/MultiEdit/Bash.
 * Appends one hash-chained JSONL entry per mutating tool call to
 * <project>/.anvil/ops.receipts.jsonl — the same append-only cryptographic
 * logging discipline as ops.receipts in Studio, at the agent layer.
 *
 * Chain: entry.h = sha256(prevHash + "\n" + canonicalJson(entry_without_h))
 * Genesis prevHash = "ANVIL-GENESIS". Verify with: node receipt.mjs --verify
 *
 * Always exits 0 — logging must never interrupt the agent loop.
 */

import { readFileSync, existsSync, mkdirSync, appendFileSync, statSync, createReadStream } from "node:fs";
import { createHash } from "node:crypto";
import { createInterface } from "node:readline";
import path from "node:path";

const GENESIS = "ANVIL-GENESIS";

function sha256(s) {
  return createHash("sha256").update(s, "utf8").digest("hex");
}

function canonical(obj) {
  if (obj === null || typeof obj !== "object") return JSON.stringify(obj);
  if (Array.isArray(obj)) return "[" + obj.map(canonical).join(",") + "]";
  return (
    "{" +
    Object.keys(obj)
      .sort()
      .map((k) => JSON.stringify(k) + ":" + canonical(obj[k]))
      .join(",") +
    "}"
  );
}

function receiptPath(projectDir) {
  const dir = path.join(projectDir, ".anvil");
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return path.join(dir, "ops.receipts.jsonl");
}

function lastHash(file) {
  if (!existsSync(file) || statSync(file).size === 0) return GENESIS;
  const data = readFileSync(file, "utf8");
  const lines = data.split("\n").filter((l) => l.trim().length > 0);
  if (lines.length === 0) return GENESIS;
  try {
    const last = JSON.parse(lines[lines.length - 1]);
    return typeof last.h === "string" ? last.h : GENESIS;
  } catch {
    return GENESIS;
  }
}

async function verify(file) {
  if (!existsSync(file)) {
    console.log("no receipts file at " + file);
    process.exit(0);
  }
  let prev = GENESIS;
  let n = 0;
  const rl = createInterface({ input: createReadStream(file, "utf8"), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    n++;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      console.error(`CHAIN BROKEN at line ${n}: unparseable JSON`);
      process.exit(1);
    }
    const { h, ...body } = entry;
    const expect = sha256(prev + "\n" + canonical(body));
    if (h !== expect) {
      console.error(`CHAIN BROKEN at line ${n}: expected ${expect}, found ${h}`);
      process.exit(1);
    }
    prev = h;
  }
  console.log(`chain OK — ${n} receipts, head ${prev.slice(0, 16)}…`);
  process.exit(0);
}

function summarizeToolInput(toolName, toolInput) {
  if (!toolInput || typeof toolInput !== "object") return {};
  if (toolName === "Bash") {
    const cmd = String(toolInput.command || "");
    return { command_sha256: sha256(cmd), command_head: cmd.slice(0, 200) };
  }
  const out = {};
  if (toolInput.file_path) {
    out.file = String(toolInput.file_path);
    try {
      if (existsSync(out.file)) out.file_sha256 = sha256(readFileSync(out.file, "utf8"));
    } catch {
      /* binary or unreadable — hash omitted, path still recorded */
    }
  }
  return out;
}

function main() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const file = receiptPath(projectDir);

  if (process.argv.includes("--verify")) {
    verify(file);
    return;
  }

  const gateIdx = process.argv.indexOf("--gate");
  if (gateIdx !== -1) {
    const gate = process.argv[gateIdx + 1];
    if (!gate) {
      process.stderr.write("usage: receipt.mjs --gate <G0..G7|PATH-INIT|RETROFIT-AUDIT|G<n>-WAIVED> [--note <text>]\n");
      process.exit(1);
    }
    const noteIdx = process.argv.indexOf("--note");
    const note = noteIdx !== -1 ? String(process.argv[noteIdx + 1] || "") : "";
    const body = {
      ts: new Date().toISOString(),
      session: "operator-gate",
      event: "Gate",
      gate: String(gate),
      note: note.slice(0, 1000),
      cwd: projectDir
    };
    const prev = lastHash(file);
    const h = sha256(prev + "\n" + canonical(body));
    appendFileSync(file, JSON.stringify({ ...body, h }) + "\n", "utf8");
    console.log(`gate ${gate} receipted — head ${h.slice(0, 16)}…`);
    process.exit(0);
  }

  let input = null;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    process.exit(0);
  }
  if (!input || typeof input !== "object") process.exit(0);

  const toolName = String(input.tool_name || "unknown");
  const body = {
    ts: new Date().toISOString(),
    session: String(input.session_id || "unknown"),
    event: "PostToolUse",
    tool: toolName,
    ...summarizeToolInput(toolName, input.tool_input),
    override: process.env.ANVIL_OVERRIDE === "1" ? true : undefined
  };
  // strip undefined so canonicalization is stable
  for (const k of Object.keys(body)) if (body[k] === undefined) delete body[k];

  const prev = lastHash(file);
  const h = sha256(prev + "\n" + canonical(body));
  appendFileSync(file, JSON.stringify({ ...body, h }) + "\n", "utf8");
  process.exit(0);
}

main();
