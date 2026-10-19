#!/usr/bin/env node
// check-candidate.mjs — /diagram's pre-finalize evidence check for a codebase
// diagram (specs/diagram-skill.md D8, AC5).
//
//   node check-candidate.mjs <candidate.json> --repo-root <dir>
//
// Archify verifies cited ranges against the pinned revision; this check runs
// before `finalize` and refuses what Archify would accept but jplugin does not:
// a candidate with no `meta.repository`, a revision other than the
// repository's HEAD, or a primary element without `sources`. Silent on success
// (exit 0); every problem on stderr and exit 1; exit 2 for a usage error.

import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

// The elements that carry `sources` per diagram type — upstream's rule
// (references/repository-authoring.md § Evidence by diagram type).
const PRIMARY_ELEMENTS = {
  architecture: "components",
  workflow: "nodes",
  sequence: "participants",
  dataflow: "nodes",
  lifecycle: "states",
  erd: "entities",
  tree: "nodes",
  class: "types",
  timeline: "events",
  waterfall: "spans",
};

function fail(message, status) {
  process.stderr.write(`archify: ${message}\n`);
  process.exit(status);
}

function parseArgs(argv) {
  let candidate = null;
  let repoRoot = null;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--repo-root") {
      repoRoot = argv[i + 1];
      i += 1;
    } else if (candidate === null) {
      candidate = argv[i];
    } else {
      fail(`usage: check-candidate.mjs <candidate.json> --repo-root <dir> (unexpected ${argv[i]})`, 2);
    }
  }
  if (!candidate || !repoRoot) fail("usage: check-candidate.mjs <candidate.json> --repo-root <dir>", 2);
  return { candidate, repoRoot };
}

function readCandidate(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    return fail(`cannot read ${path}: ${error.message}`, 2);
  }
}

function repositoryHead(repoRoot) {
  try {
    return execFileSync("git", ["-C", repoRoot, "rev-parse", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  } catch (error) {
    return fail(`${repoRoot} is not a git repository with a HEAD: ${error.message.trim()}`, 2);
  }
}

// A citation is a path and a line: `--refresh` re-reads the cited range, so a
// path alone leaves it nothing to re-anchor from.
function hasSources(element) {
  return Array.isArray(element.sources) && element.sources.length > 0
    && element.sources.every((source) => source && typeof source.path === "string" && source.path.length > 0
      && Number.isInteger(source.line) && source.line > 0);
}

function problems(candidate, head) {
  const found = [];
  const repository = candidate.meta && candidate.meta.repository;
  if (!repository || typeof repository !== "object") {
    found.push("meta.repository is missing: a codebase diagram pins the repository url and revision");
  } else if (repository.revision !== head) {
    found.push(`meta.repository.revision is ${repository.revision}, but the repository HEAD is ${head}: re-author against HEAD`);
  }
  const key = PRIMARY_ELEMENTS[candidate.diagram_type];
  if (!key) {
    found.push(`diagram_type ${JSON.stringify(candidate.diagram_type)} is not one of Archify's diagram types`);
    return found;
  }
  const elements = Array.isArray(candidate[key]) ? candidate[key] : [];
  if (elements.length === 0) found.push(`${key} is empty: nothing to cite`);
  elements.forEach((element, index) => {
    if (!hasSources(element)) {
      found.push(`${key}[${index}] ${JSON.stringify(element.id ?? element.label ?? "")} has no sources: every ${key.replace(/s$/, "")} of a codebase diagram cites a path and line`);
    }
  });
  return found;
}

const args = parseArgs(process.argv.slice(2));
const found = problems(readCandidate(args.candidate), repositoryHead(args.repoRoot));
if (found.length > 0) {
  for (const problem of found) process.stderr.write(`archify: ${problem}\n`);
  process.exit(1);
}
