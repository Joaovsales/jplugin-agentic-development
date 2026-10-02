"""Project UI workflow, append-only evidence records, and CI artifact lookup."""

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from uuid import uuid4

from visual_check import validate_manifest


TEMPLATE = Path(__file__).resolve().parent.parent / "templates/jplugin-ui-evidence.yml"
MARKER = "# jplugin-ui-template-sha256: "


def managed_workflow():
    body = TEMPLATE.read_bytes()
    return (MARKER + hashlib.sha256(body).hexdigest() + "\n").encode() + body


def verified_managed_workflow(content):
    header, separator, body = content.partition(b"\n")
    if not separator or not header.startswith(MARKER.encode()):
        return False
    return header[len(MARKER):].decode() == hashlib.sha256(body).hexdigest()


def install_workflow(project, update=False):
    project = Path(project).resolve()
    target = project / ".github/workflows/jplugin-ui-evidence.yml"
    content = managed_workflow()
    if target.is_symlink() or not target.parent.resolve().is_relative_to(project):
        raise ValueError("UI evidence workflow path leaves the project")
    if target.exists():
        current = target.read_bytes()
        if current == content:
            return target
        if not update or not verified_managed_workflow(current):
            raise ValueError("existing UI evidence workflow differs; explicit safe update required")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".yml.tmp")
    temporary.write_bytes(content)
    temporary.replace(target)
    return target


def timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_artifact(run, artifact, sha, pr_number):
    expected = f"jplugin-ui-pr-{pr_number}-{sha}"
    if run.get("head_sha") != sha or run.get("conclusion") != "success":
        raise ValueError("CI visual run did not pass on the reviewed commit")
    if run.get("event") != "pull_request" or artifact.get("name") != expected:
        raise ValueError("CI artifact does not match the PR and commit")
    if artifact.get("expired") or artifact.get("size_in_bytes", 0) <= 0:
        raise ValueError("CI artifact is expired or empty")
    retained = timestamp(artifact["expires_at"]) - timestamp(artifact["created_at"])
    if retained < timedelta(days=30) - timedelta(minutes=5):
        raise ValueError("CI artifact is not retained for 30 days")
    return True


def artifact_review_link(slug, run, artifact):
    if not valid_slug(slug):
        raise ValueError("invalid GitHub repository slug")
    return f"https://github.com/{slug}/actions/runs/{run['id']}/artifacts/{artifact['id']}"


def valid_slug(slug):
    return bool(re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", slug)) and all(
        part not in (".", "..") for part in slug.split("/"))


def github_api(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True,
                            timeout=30, check=True)
    return json.loads(result.stdout)


def lookup_ci_artifact(slug, pr_number, sha):
    if not valid_slug(slug):
        raise ValueError("invalid GitHub repository slug")
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or not str(pr_number).isdigit():
        raise ValueError("invalid PR or commit for artifact lookup")
    runs = github_api(f"repos/{slug}/actions/workflows/jplugin-ui-evidence.yml/runs"
                      f"?event=pull_request&head_sha={sha}&per_page=100")
    for run in runs.get("workflow_runs", []):
        if run.get("head_sha") != sha or run.get("conclusion") != "success":
            continue
        artifacts = github_api(f"repos/{slug}/actions/runs/{run['id']}/artifacts")
        for artifact in artifacts.get("artifacts", []):
            try:
                validate_artifact(run, artifact, sha, pr_number)
            except (KeyError, ValueError):
                continue
            return artifact_review_link(slug, run, artifact)
    raise ValueError("PublicationUnavailable: no valid CI visual artifact for PR commit")


def append_ui_entry(log, feature, sha, state, output, review_link, disposition):
    output = Path(output).resolve()
    workspace = Path(log).resolve().parent.parent
    if not output.is_relative_to(workspace):
        raise ValueError("PublicationUnavailable: captures are outside the project workspace")
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    validate_manifest(output, manifest, [state])
    local_link = Path(review_link)
    if not local_link.is_absolute():
        local_link = workspace / local_link
    local_link = local_link.resolve()
    local_ok = local_link.is_relative_to(workspace) and local_link.exists()
    github_link = re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+/actions/runs/\d+/artifacts/\d+", review_link)
    if disposition != "pass" or not review_link or not (github_link or local_ok):
        raise ValueError("PublicationUnavailable: unresolved defect or missing review link")
    evidence = manifest["states"][state]
    now = datetime.now(timezone.utc)
    run_id = f"{now:%Y%m%dT%H%M%SZ}-{uuid4().hex[:8]}"
    record = (f"\n## E2E Walkthrough — {feature} — {now:%Y-%m-%d} {sha[:12]}\n"
              f"Run ID: {run_id}\n\n### AC-UI-{state}\nTier: VISUAL\n"
              f"UI State: {state}\nResult: PASS\n"
              f"Screenshot: {output / evidence['desktop']}\n"
              f"Mobile Screenshot: {output / evidence['mobile']}\n"
              f"Visual disposition: {disposition}\nReview Link: {review_link}\n")
    log = Path(log)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as stream:
        stream.write(record)
    return run_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    install = sub.add_parser("install-workflow")
    install.add_argument("--project", required=True)
    install.add_argument("--update", action="store_true")
    lookup = sub.add_parser("lookup")
    for flag in ("slug", "pr", "sha"):
        lookup.add_argument(f"--{flag}", required=True)
    args = parser.parse_args()
    if args.action == "install-workflow":
        print(install_workflow(args.project, update=args.update))
    else:
        print(lookup_ci_artifact(args.slug, args.pr, args.sha))
    return 0


if __name__ == "__main__":
    sys.exit(main())
