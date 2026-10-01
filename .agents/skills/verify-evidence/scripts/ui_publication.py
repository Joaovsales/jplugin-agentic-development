"""Project UI workflow, append-only evidence records, and CI artifact lookup."""

import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
from uuid import uuid4

from visual_check import validate_manifest


TEMPLATE = Path(__file__).resolve().parent.parent / "templates/jplugin-ui-evidence.yml"


def install_workflow(project):
    target = Path(project) / ".github/workflows/jplugin-ui-evidence.yml"
    content = TEMPLATE.read_bytes()
    if target.exists():
        if target.read_bytes() != content:
            raise ValueError("existing UI evidence workflow differs; review before updating")
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
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
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", slug):
        raise ValueError("invalid GitHub repository slug")
    return f"https://github.com/{slug}/actions/runs/{run['id']}/artifacts/{artifact['id']}"


def github_api(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True,
                            timeout=30, check=True)
    return json.loads(result.stdout)


def lookup_ci_artifact(slug, pr_number, sha):
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
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    validate_manifest(output, manifest, [state])
    if disposition != "pass" or not review_link:
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
    sub.add_parser("install-workflow").add_argument("--project", required=True)
    lookup = sub.add_parser("lookup")
    for flag in ("slug", "pr", "sha"):
        lookup.add_argument(f"--{flag}", required=True)
    args = parser.parse_args()
    if args.action == "install-workflow":
        print(install_workflow(args.project))
    else:
        print(lookup_ci_artifact(args.slug, args.pr, args.sha))
    return 0


if __name__ == "__main__":
    sys.exit(main())
