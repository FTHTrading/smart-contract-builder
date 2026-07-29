// Regenerate contracts/rwa/*/*.sol from Unykorn Studio's canonical sources.
// Studio holds the source of truth as TypeScript const strings; this script
// extracts them into pure .sol files so the Foundry project can compile
// against them independently.
//
// Run when Studio's contract sources change:
//   node scripts/extract-from-studio.mjs
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = dirname(HERE);
const STUDIO = join(REPO, "..", "platforms", "unykorn-studio", "lib", "templates");

/** [studioSubdir, [ [const_name, out_relative_path_in_repo] ]] */
const MAP = [
  ["draw-escrow", [
    ["IWAIVER_ATTESTOR_SOL", "contracts/rwa/draw-escrow/IWaiverAttestor.sol"],
    ["MILESTONE_REGISTRY_SOL", "contracts/rwa/draw-escrow/MilestoneRegistry.sol"],
    ["DRAW_ESCROW_SOL", "contracts/rwa/draw-escrow/DrawEscrow.sol"],
    ["LOCAL_TEST_TOKEN_SOL", "contracts/rwa/draw-escrow/LocalTestToken.sol"],
  ]],
  ["permissioned-security", [
    ["IDENTITY_REGISTRY_SOL", "contracts/rwa/permissioned-security/IdentityRegistry.sol"],
    ["CLAIM_TOPICS_REGISTRY_SOL", "contracts/rwa/permissioned-security/ClaimTopicsRegistry.sol"],
    ["PERMISSIONED_TOKEN_SOL", "contracts/rwa/permissioned-security/PermissionedToken.sol"],
  ]],
  ["reit-distribution", [
    ["DISTRIBUTION_TOKEN_SOL", "contracts/rwa/reit-distribution/DistributionToken.sol"],
    ["REIT_DISTRIBUTOR_SOL", "contracts/rwa/reit-distribution/REITDistributor.sol"],
  ]],
  ["cmbs-tranche", [
    ["CMBS_WATERFALL_SOL", "contracts/rwa/cmbs-tranche/CMBSWaterfall.sol"],
  ]],
  ["srec-token", [
    ["SREC_TOKEN_SOL", "contracts/rwa/srec-token/SRECToken.sol"],
  ]],
  ["chainlink-oracle", [
    ["CHAINLINK_ORACLE_SOL", "contracts/rwa/chainlink-oracle/RWAOracle.sol"],
  ]],
];

function extractConst(tsContent, constName) {
  const re = new RegExp("export const " + constName + " = `([\\s\\S]*?)`;", "m");
  const m = tsContent.match(re);
  if (!m) throw new Error(`const ${constName} not found`);
  return m[1];
}

let written = 0;
for (const [studioDir, entries] of MAP) {
  const srcTs = join(STUDIO, studioDir, "sources.ts");
  if (!existsSync(srcTs)) {
    console.warn(`  ! studio source missing: ${srcTs}`);
    continue;
  }
  const content = readFileSync(srcTs, "utf8");
  for (const [constName, outRel] of entries) {
    try {
      const sol = extractConst(content, constName);
      const outAbs = join(REPO, outRel);
      mkdirSync(dirname(outAbs), { recursive: true });
      writeFileSync(outAbs, sol);
      console.log(`  ✓ ${outRel}`);
      written++;
    } catch (err) {
      console.error(`  ✗ ${outRel}: ${err.message}`);
    }
  }
}

console.log(`\n${written} .sol files written from Studio's canonical sources.`);
