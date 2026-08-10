#!/usr/bin/env node
/**
 * ANVIL quality — PostToolUse on Write/Edit/MultiEdit.
 * Runs the fastest available checker for the file that was just written and,
 * on failure, exits 2 so the checker output is fed straight back to Claude
 * for an immediate fix — the claudekit behavior, with zero third-party code.
 *
 * Design constraints:
 *  - Never blocks on missing toolchains: if a checker binary isn't present,
 *    the file passes silently. Guards must not depend on a machine's setup.
 *  - Hard timeout per check (20s) so a slow cargo build can't stall the loop.
 *  - Only checks the single touched file where the toolchain allows it;
 *    Rust falls back to `cargo check` on the owning crate.
 */

import { readFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";

const TIMEOUT_MS = 20_000;
const IS_WIN = process.platform === "win32";

function readStdin() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return null;
  }
}

function run(cmd, args, cwd) {
  return spawnSync(cmd, args, {
    cwd,
    timeout: TIMEOUT_MS,
    encoding: "utf8",
    shell: IS_WIN, // resolve .cmd shims (npx, tsc) on Windows
    windowsHide: true
  });
}

function which(bin) {
  const probe = run(IS_WIN ? "where" : "which", [bin], process.cwd());
  return probe.status === 0;
}

function findUp(startDir, marker) {
  let dir = startDir;
  for (;;) {
    if (existsSync(path.join(dir, marker))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function fail(label, res) {
  const out = [res.stdout, res.stderr].filter(Boolean).join("\n").trim();
  process.stderr.write(
    `[ANVIL QUALITY] ${label} failed for the file just written. Fix these before continuing:\n` +
    `${out.slice(0, 6000)}\n`
  );
  process.exit(2);
}

function checkTsJs(file, dir) {
  // 1) Syntax gate: node --check for plain JS; tsc --noEmit for TS if available.
  const ext = path.extname(file).toLowerCase();
  if ([".js", ".mjs", ".cjs"].includes(ext)) {
    const res = run("node", ["--check", file], dir);
    if (res.status !== 0 && res.status !== null) fail("node --check", res);
  }
  if ([".ts", ".tsx"].includes(ext)) {
    const pkgDir = findUp(dir, "tsconfig.json");
    if (pkgDir && which("npx")) {
      const res = run("npx", ["--no-install", "tsc", "--noEmit", "--pretty", "false"], pkgDir);
      // status null => timeout: skip silently, do not stall the loop
      if (res.status !== 0 && res.status !== null && /error TS\d+/.test((res.stdout || "") + (res.stderr || ""))) {
        fail("tsc --noEmit", res);
      }
    }
  }
  // 2) Lint gate: eslint on the single file if a config exists.
  const eslintRoot =
    findUp(dir, "eslint.config.js") ||
    findUp(dir, "eslint.config.mjs") ||
    findUp(dir, ".eslintrc.json") ||
    findUp(dir, ".eslintrc.cjs");
  if (eslintRoot && which("npx")) {
    const res = run("npx", ["--no-install", "eslint", "--no-color", file], eslintRoot);
    if (res.status !== 0 && res.status !== null && (res.stdout || res.stderr)) {
      fail("eslint", res);
    }
  }
}

function checkRust(file, dir) {
  const crateDir = findUp(dir, "Cargo.toml");
  if (!crateDir || !which("cargo")) return;
  const fmt = run("cargo", ["fmt", "--", "--check", file], crateDir);
  if (fmt.status !== 0 && fmt.status !== null && (fmt.stdout || "").trim()) {
    // Formatting drift: auto-fix instead of bouncing it back.
    run("cargo", ["fmt", "--", file], crateDir);
  }
  const res = run("cargo", ["check", "--quiet", "--message-format=short"], crateDir);
  if (res.status !== 0 && res.status !== null) fail("cargo check", res);
}

function checkPython(file, dir) {
  if (which("ruff")) {
    const res = run("ruff", ["check", "--no-cache", file], dir);
    if (res.status !== 0 && res.status !== null) fail("ruff check", res);
    return;
  }
  const res = run(IS_WIN ? "python" : "python3", ["-m", "py_compile", file], dir);
  if (res.status !== 0 && res.status !== null) fail("py_compile", res);
}

function checkSolidity(file, dir) {
  const foundryRoot = findUp(dir, "foundry.toml");
  if (foundryRoot && which("forge")) {
    const res = run("forge", ["build", "--silent"], foundryRoot);
    if (res.status !== 0 && res.status !== null) fail("forge build", res);
    return;
  }
  if (which("solc")) {
    const res = run("solc", ["--stop-after", "parsing", file], dir);
    if (res.status !== 0 && res.status !== null) fail("solc parse", res);
  }
}

function checkJson(file, dir) {
  try {
    JSON.parse(readFileSync(file, "utf8"));
  } catch (e) {
    process.stderr.write(`[ANVIL QUALITY] invalid JSON in ${file}: ${e.message}\n`);
    process.exit(2);
  }
}

function main() {
  const input = readStdin();
  if (!input) process.exit(0);
  const file = input.tool_input && input.tool_input.file_path;
  if (typeof file !== "string" || !existsSync(file)) process.exit(0);

  const dir = path.dirname(path.resolve(file));
  const ext = path.extname(file).toLowerCase();

  try {
    if ([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"].includes(ext)) checkTsJs(file, dir);
    else if (ext === ".rs") checkRust(file, dir);
    else if (ext === ".py") checkPython(file, dir);
    else if (ext === ".sol") checkSolidity(file, dir);
    else if (ext === ".json") checkJson(file, dir);
  } catch (e) {
    // A crashed checker must never punish the agent loop.
    process.stderr.write(`[ANVIL QUALITY] checker crashed (${e.message}); passing.\n`);
  }
  process.exit(0);
}

main();
