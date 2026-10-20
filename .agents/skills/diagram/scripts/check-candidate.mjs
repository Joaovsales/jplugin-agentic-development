#!/usr/bin/env node
// check-candidate.mjs — /diagram's pre-finalize evidence check for a codebase
// diagram (specs/diagram-skill.md D8, AC5).
//
//   node check-candidate.mjs <candidate.json> --repo-root <dir> --schemas <dir>
//
// Archify verifies cited ranges against the pinned revision; this check runs
// before `finalize` and refuses what Archify would accept but jplugin does not:
// a candidate with no `meta.repository`, a revision other than the
// repository's HEAD, or a primary element without `sources`. Which collection
// is primary is upstream's rule, read from upstream's schema under --schemas
// rather than restated here (D17). Silent on success (exit 0); every problem
// on stderr and exit 1; exit 2 for a usage error.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const DIAGRAM_TYPE_RE = /^[a-z]+$/;

function fail(message, status) {
  process.stderr.write(`archify: ${message}\n`);
  process.exit(status);
}

function parseArgs(argv) {
  const parsed = { candidate: null, repoRoot: null, schemas: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--repo-root") {
      parsed.repoRoot = argv[i + 1];
      i += 1;
    } else if (argv[i] === "--schemas") {
      parsed.schemas = argv[i + 1];
      i += 1;
    } else if (parsed.candidate === null) {
      parsed.candidate = argv[i];
    } else {
      fail(`usage: check-candidate.mjs <candidate.json> --repo-root <dir> --schemas <dir> (unexpected ${argv[i]})`, 2);
    }
  }
  if (!parsed.candidate || !parsed.repoRoot || !parsed.schemas) {
    fail("usage: check-candidate.mjs <candidate.json> --repo-root <dir> --schemas <dir>", 2);
  }
  return parsed;
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

// The type's primary collection — components, nodes, participants, states,
// entities, types, events or spans — is the one top-level array in its schema
// whose items carry `sources`; `cards` is shared and arrives as a $ref.
function primaryKey(schemasDir, diagramType) {
  if (typeof diagramType !== "string" || !DIAGRAM_TYPE_RE.test(diagramType)) {
    return { error: `diagram_type ${JSON.stringify(diagramType)} is not a diagram type name` };
  }
  const schemaPath = join(schemasDir, `${diagramType}.schema.json`);
  let schema;
  try {
    schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  } catch {
    return { error: `diagram_type ${JSON.stringify(diagramType)} has no schema under ${schemasDir}: not one of this install's diagram types` };
  }
  const keys = Object.entries(schema.properties ?? {})
    .filter(([, value]) => value.type === "array" && value.items?.properties && "sources" in value.items.properties)
    .map(([key]) => key);
  if (keys.length !== 1) {
    return { error: `${schemaPath} names ${keys.length} arrays whose items carry sources; expected exactly one` };
  }
  return { key: keys[0] };
}

// A citation is a path and a line: `--refresh` re-reads the cited range, so a
// path alone leaves it nothing to re-anchor from.
function hasSources(element) {
  return Array.isArray(element.sources) && element.sources.length > 0
    && element.sources.every((source) => source && typeof source.path === "string" && source.path.length > 0
      && Number.isInteger(source.line) && source.line > 0);
}

function problems(candidate, head, schemasDir) {
  const found = [];
  const repository = candidate.meta && candidate.meta.repository;
  if (!repository || typeof repository !== "object") {
    found.push("meta.repository is missing: a codebase diagram pins the repository url and revision");
  } else if (repository.revision !== head) {
    found.push(`meta.repository.revision is ${repository.revision}, but the repository HEAD is ${head}: re-author against HEAD`);
  }
  const primary = primaryKey(schemasDir, candidate.diagram_type);
  if (primary.error) {
    found.push(primary.error);
    return found;
  }
  const key = primary.key;
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
const found = problems(readCandidate(args.candidate), repositoryHead(args.repoRoot), args.schemas);
if (found.length > 0) {
  for (const problem of found) process.stderr.write(`archify: ${problem}\n`);
  process.exit(1);
}
