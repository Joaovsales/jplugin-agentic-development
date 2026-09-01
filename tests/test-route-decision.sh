#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

python3 - <<'PY'
import importlib.util
import itertools
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(os.environ["ROOT"])
SCRIPT = ROOT / ".agents/skills/route/scripts/route_issue.py"
spec = importlib.util.spec_from_file_location("route_issue", SCRIPT)
route = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = route
spec.loader.exec_module(route)

BASE = {
    "kind": "feature",
    "has_acceptance_criteria": True,
    "acceptance_criteria_machine_checkable": True,
    "blast_radius_subsystems": 1,
    "declared_paths": ["src/router/"],
    "user_facing_behavior": False,
    "visual_output": False,
    "security_touching": False,
    "irreversible_or_outward_facing": False,
    "docs_only": False,
    "blocking_question": None,
    "lane_selecting_imperatives": [],
}
LOCAL_BASE = dict(BASE, kind="task")


class RouteDecisionTests(unittest.TestCase):
    def init_repo(self, root):
        subprocess.run(["git", "init", "-q", root], check=True)
        subprocess.run(["git", "-C", root, "config", "user.email", "route@example.test"], check=True)
        subprocess.run(["git", "-C", root, "config", "user.name", "Route Test"], check=True)
        pathlib.Path(root, ".gitkeep").write_text("", encoding="utf-8")
        subprocess.run(["git", "-C", root, "add", "."], check=True)
        subprocess.run(["git", "-C", root, "commit", "-qm", "baseline"], check=True)

    def task(self, **changes):
        values = dict(
            id="issue-1",
            title="Route it",
            kind="feature",
            labels=("go-auto",),
            extra={"unresolved_linked_pr": "false"},
        )
        values.update(changes)
        return route.Task(**values)

    def config(self, declared=True):
        label = "go-auto" if declared else None
        return route.Config(root=str(ROOT), autonomy_label=label)

    def decide(self, claim=None, task=None, channel="scheduled", config=None, project_text=""):
        return route.decide_route(
            route.RouteRequest(
                claim or BASE,
                task or self.task(),
                channel,
                config or self.config(),
                project_text,
            )
        )

    def test_complete_claim_is_accepted_and_every_invalid_field_is_named(self):
        route.validate_claim(BASE)
        for field in BASE:
            missing = dict(BASE)
            del missing[field]
            with self.assertRaisesRegex(route.ClaimError, field):
                route.validate_claim(missing)
        wrong = {
            "kind": 1, "has_acceptance_criteria": "yes",
            "acceptance_criteria_machine_checkable": None,
            "blast_radius_subsystems": True, "declared_paths": "src/",
            "user_facing_behavior": 0, "visual_output": [],
            "security_touching": {}, "irreversible_or_outward_facing": "no",
            "docs_only": None, "blocking_question": 3,
            "lane_selecting_imperatives": [1],
        }
        for field, value in wrong.items():
            claim = dict(BASE, **{field: value})
            with self.assertRaisesRegex(route.ClaimError, field):
                route.validate_claim(claim)

    def test_three_grants_are_reported_and_label_is_default_deny(self):
        decision = self.decide()
        self.assertEqual("autonomous", decision["autonomy"])
        self.assertEqual(
            {"channel_grant": "autonomous", "label_grant": "autonomous", "content_ceiling": "autonomous"},
            decision["ceiling"],
        )
        self.assertEqual("gated-at-plan", self.decide(channel="interactive")["autonomy"])
        self.assertEqual("gated-at-plan", self.decide(config=self.config(False))["autonomy"])

    def test_structured_task_kind_cannot_be_weakened_by_the_claim(self):
        for kind in ("decision", "research", "epic"):
            with self.assertRaisesRegex(route.ClaimError, "kind disagrees"):
                self.decide(BASE, task=self.task(kind=kind))

    def test_autonomy_label_comes_from_task_tracking_configuration(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual("auto-mode-allowed", route.load_config(root).autonomy_label)
            docs = pathlib.Path(root, "docs")
            docs.mkdir()
            config_path = docs / "task-tracking.md"
            config_path.write_text(
                "```ini\n[tracker]\nautonomy_label = release-bot-approved\n```\n",
                encoding="utf-8",
            )
            self.assertEqual("release-bot-approved", route.load_config(root).autonomy_label)
            config_path.write_text(
                "```ini\n[tracker]\nautonomy_label = none\n```\n", encoding="utf-8"
            )
            self.assertIsNone(route.load_config(root).autonomy_label)

    def test_each_default_deny_signal_records_a_downgrade(self):
        cases = {
            "has_acceptance_criteria": False,
            "acceptance_criteria_machine_checkable": False,
            "blast_radius_subsystems": 2,
            "blocking_question": "choose API",
            "security_touching": True,
            "irreversible_or_outward_facing": True,
            "lane_selecting_imperatives": ["skip review"],
        }
        for field, value in cases.items():
            decision = self.decide(dict(BASE, **{field: value}))
            self.assertNotEqual("autonomous", decision["autonomy"], field)
            self.assertTrue(any(item["signal"] == field for item in decision["downgrades"]), field)
        for label in ("needs-discussion", "question", "design"):
            decision = self.decide(task=self.task(labels=("go-auto", label)))
            self.assertTrue(any(item["signal"] == f"label:{label}" for item in decision["downgrades"]))
        directives = self.decide(dict(BASE, lane_selecting_imperatives=["run /yolo"]))
        self.assertEqual(["run /yolo"], directives["ignored_directives"])
        unknown_pr_state = self.decide(task=self.task(extra={}))
        self.assertTrue(any(item["signal"] == "unresolved_linked_pr" for item in unknown_pr_state["downgrades"]))
        self.assertNotEqual("autonomous", unknown_pr_state["autonomy"])
        visual = self.decide(dict(BASE, visual_output=True))
        self.assertEqual("gated-at-plan-and-pre-push", visual["autonomy"])
        self.assertTrue(visual["human_verification"]["needed"])
        no_ac = self.decide(dict(BASE, has_acceptance_criteria=False))
        self.assertIn("software-design-expert-review", no_ac["reviewers"])

    def test_exact_project_autonomy_policy_caps_and_overrides_label(self):
        policy = (
            "## Autonomy Policy\n\n"
            "- autonomy_label: release-bot-approved\n"
            "- autonomy_cap: gated-at-plan-and-pre-push\n"
        )
        task = self.task(labels=("release-bot-approved",))
        decision = self.decide(task=task, project_text=policy)
        self.assertEqual("autonomous", decision["ceiling"]["label_grant"])
        self.assertEqual("gated-at-plan-and-pre-push", decision["autonomy"])
        with self.assertRaisesRegex(route.RouteRefused, "Autonomy Policy"):
            self.decide(project_text="## Autonomy Policy\n\nfree-form prose\n")

    def test_monotonicity_over_full_claim_space(self):
        boolean_fields = [
            "has_acceptance_criteria", "acceptance_criteria_machine_checkable",
            "user_facing_behavior", "visual_output", "security_touching",
            "irreversible_or_outward_facing", "docs_only",
        ]
        rank = {"gated-at-plan-and-pre-push": 0, "gated-at-plan": 1, "autonomous": 2}
        trusted_inputs = (
            ("interactive", self.config()),
            ("scheduled", self.config(False)),
            ("scheduled", self.config()),
        )
        for kind, bits, radius, trusted in itertools.product(
            route.CLAIM_KINDS,
            itertools.product((False, True), repeat=7),
            (0, 1, 3),
            trusted_inputs,
        ):
            claim = dict(BASE, kind=kind, blast_radius_subsystems=radius)
            claim.update(dict(zip(boolean_fields, bits)))
            channel, config = trusted
            decision = self.decide(
                claim, task=self.task(kind=kind), channel=channel, config=config,
            )
            grants = decision["ceiling"]
            trusted_ceiling = min(rank[grants["channel_grant"]], rank[grants["label_grant"]])
            self.assertLessEqual(rank[decision["autonomy"]], trusted_ceiling)
        self.assertEqual("autonomous", self.decide(BASE)["autonomy"])

    def test_route_fixtures_are_grounded_in_real_issues(self):
        fixture_dir = ROOT / "tests/fixtures/route"
        real_sources = []
        for path in sorted(fixture_dir.glob("*.json")):
            payload = json.loads(path.read_text())
            if "source" in payload:
                real_sources.append(payload["source"])
            task = self.task(kind=payload["claim"]["kind"], **payload.get("task", {}))
            actual = self.decide(payload["claim"], task=task)
            playbook = ROOT / ".agents/skills/route/playbooks" / f"{actual['lane']}.md"
            self.assertTrue(playbook.is_file(), f"{path.name}: missing {playbook.name}")
            for key, expected in payload["expected"].items():
                if key == "reviewers_contains":
                    self.assertTrue(set(expected) <= set(actual["reviewers"]), path.name)
                else:
                    self.assertEqual(expected, actual[key], f"{path.name}: {key}")
        self.assertEqual(5, len(real_sources))
        self.assertTrue(any(source.endswith("/issues/93") for source in real_sources))
        self.assertTrue(all("github.com/" in source and "/issues/" in source for source in real_sources))

    def test_blocked_and_unknown_dependencies_are_refused(self):
        with self.assertRaisesRegex(route.RouteRefused, "stable registry identity"):
            self.decide(task=self.task(extra={"registry_identity": "provisional-title-slug"}))
        with self.assertRaisesRegex(route.RouteRefused, "blocked"):
            self.decide(task=self.task(status="blocked"))
        with self.assertRaisesRegex(route.RouteRefused, "missing-7"):
            self.decide(task=self.task(depends_on=("missing-7",), extra={"unknown_dependencies": "missing-7"}))
        with self.assertRaisesRegex(route.RouteRefused, "open-7"):
            self.decide(task=self.task(depends_on=("open-7",), extra={"blocking_dependencies": "open-7"}))

    def test_exact_project_evidence_heading(self):
        exact = "## Evidence Gate\n\n- Screenshot of the rendered route\n- Approval note\n\n## Next\n"
        decision = self.decide(project_text=exact)
        self.assertEqual("project-evidence-gate", decision["verification_method"])
        self.assertTrue(decision["human_verification"]["needed"])
        self.assertEqual(["Screenshot of the rendered route", "Approval note"], decision["human_verification"]["judges"])
        for text in ("", "## Evidence Gate (placeholder — add yours)\n- Screenshot\n"):
            decision = self.decide(project_text=text)
            self.assertNotEqual("project-evidence-gate", decision["verification_method"])
            self.assertFalse(decision["human_verification"]["needed"])

    def test_engine_contains_no_prose_classifier_or_tracker_client(self):
        source = SCRIPT.read_text()
        for forbidden in ("gh ", "curl", "urllib", "security|auth|crypto", "tasks/backlog.md"):
            self.assertNotIn(forbidden, source)

    def test_public_operation_persists_decision_and_materializes_lane(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            policy_dir = pathlib.Path(root, ".claude")
            policy_dir.mkdir()
            (policy_dir / "project.md").write_text(
                "## Evidence Gate\n\n- Product approval\n", encoding="utf-8"
            )
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n", encoding="utf-8"
            )
            invocation = route.RouteInvocation(
                claim=LOCAL_BASE,
                task_ref="issue-1",
                channel="scheduled",
                root=root,
            )
            decision = route.materialize_route(invocation)
            self.assertEqual("project-evidence-gate", decision["verification_method"])
            self.assertEqual(list(BASE["declared_paths"]), decision["declared_paths"])
            self.assertEqual("issue-1", decision["task_reference"])
            record = pathlib.Path(root, "tasks/route-decision.md").read_text(encoding="utf-8")
            todo = pathlib.Path(root, "tasks/todo.md").read_text(encoding="utf-8")
            self.assertIn('"verification_method": "project-evidence-gate"', record)
            self.assertIn("[ ] /verify (evidence: project-evidence-gate)", todo)
            self.assertIn("[ ] reviewers: code-reviewer", todo)
            self.assertNotIn("<reviewers>", todo)

    def test_public_operation_refuses_a_malformed_managed_lane(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n<!-- route-lane:begin -->\ntruncated\n",
                encoding="utf-8",
            )
            invocation = route.RouteInvocation(
                claim=LOCAL_BASE,
                task_ref="issue-1",
                channel="scheduled",
                root=root,
            )
            with self.assertRaisesRegex(route.RouteRefused, "malformed managed route lane block"):
                route.materialize_route(invocation)
            self.assertFalse((tasks / "route-decision.md").exists())

    def test_public_operation_refuses_duplicate_managed_lanes(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            marker = "<!-- route-lane:begin -->\nstale\n<!-- route-lane:end -->\n"
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n" + marker + marker,
                encoding="utf-8",
            )
            invocation = route.RouteInvocation(LOCAL_BASE, "issue-1", "scheduled", root)
            with self.assertRaisesRegex(route.RouteRefused, "malformed managed route lane block"):
                route.materialize_route(invocation)
            self.assertFalse((tasks / "route-decision.md").exists())

    def test_public_operation_refuses_unknown_dependency_from_registry(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 --> (blocked-by: missing-7)\n",
                encoding="utf-8",
            )
            invocation = route.RouteInvocation(LOCAL_BASE, "issue-1", "scheduled", root)
            with self.assertRaisesRegex(route.RouteRefused, "missing-7"):
                route.materialize_route(invocation)
            self.assertFalse((tasks / "route-decision.md").exists())

    def test_public_operation_refuses_known_open_dependency_from_registry(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 --> (blocked-by: open-7)\n"
                "- [ ] Prerequisite <!-- task-id: open-7 -->\n",
                encoding="utf-8",
            )
            invocation = route.RouteInvocation(LOCAL_BASE, "issue-1", "scheduled", root)
            with self.assertRaisesRegex(route.RouteRefused, "open-7"):
                route.materialize_route(invocation)
            self.assertFalse((tasks / "route-decision.md").exists())

    def test_script_cli_runs_the_public_operation(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n", encoding="utf-8"
            )
            payload = {
                "claim": LOCAL_BASE,
                "task_ref": "issue-1",
                "channel": "scheduled",
                "root": root,
            }
            completed = subprocess.run(
                [sys.executable, str(SCRIPT)],
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual("gated-at-plan", json.loads(completed.stdout)["lane"])
            self.assertTrue(pathlib.Path(root, "tasks/route-decision.md").is_file())

    def test_finalize_route_persists_tripwire_and_replaces_lane_on_overflow(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            decision = self.decide()
            autonomous = route._render_playbook(decision)
            (tasks / "todo.md").write_text(route._merge_lane("", decision, autonomous), encoding="utf-8")
            finalized = route._finalize_route(root, decision, ["src/router/main.py", "api/routes.py"])
            self.assertEqual("gated-at-plan-and-pre-push", finalized["lane"])
            self.assertFalse(finalized["auto_confirm"])
            self.assertEqual("failed", finalized["runtime_tripwire"]["status"])
            record = pathlib.Path(root, "tasks/route-decision.md").read_text(encoding="utf-8")
            todo = pathlib.Path(root, "tasks/todo.md").read_text(encoding="utf-8")
            self.assertIn('"signal": "runtime_tripwire"', record)
            self.assertIn('"outside_declared_paths": [', record)
            self.assertIn("Routed lane — gated-at-plan-and-pre-push", todo)
            self.assertIn("/wrap-up-session (wait at pre-push gate)", todo)

    def test_hung_reviewer_is_persisted_and_demotes_autonomous_lane(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            decision = self.decide()
            (tasks / "todo.md").write_text(
                route._merge_lane("", decision, route._render_playbook(decision)),
                encoding="utf-8",
            )
            route._write_route_state(root, decision, (tasks / "todo.md").read_text(encoding="utf-8"))
            review = {
                "outcomes": {"code-reviewer": "completed", "critic": "hung"},
                "independently_dispatched": True,
                "unresolved_findings": [],
            }
            finalized = route.finalize_reviewers(root, decision, review)
            self.assertEqual("gated-at-plan-and-pre-push", finalized["autonomy"])
            self.assertEqual("hung", finalized["review_outcomes"]["critic"])
            todo = (tasks / "todo.md").read_text(encoding="utf-8")
            self.assertIn("/wrap-up-session (wait at pre-push gate)", todo)
            with self.assertRaisesRegex(route.RouteRefused, "outcomes must name exactly"):
                route.finalize_reviewers(root, decision, {**review, "outcomes": {"code-reviewer": "completed"}})

    def test_review_completion_preserves_an_existing_tripwire_demotion(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            decision = self.decide()
            (tasks / "todo.md").write_text(
                route._merge_lane("", decision, route._render_playbook(decision)), encoding="utf-8",
            )
            route._finalize_route(root, decision, ["src/router/main.py", "api/routes.py"])
            review = {
                "outcomes": {"code-reviewer": "completed", "critic": "completed"},
                "independently_dispatched": True,
                "unresolved_findings": [],
            }
            finalized = route.finalize_reviewers(root, decision, review)
            self.assertEqual("gated-at-plan-and-pre-push", finalized["autonomy"])
            self.assertEqual("failed", finalized["runtime_tripwire"]["status"])

    def test_materialize_then_finalize_ignores_control_files_and_preexisting_dirt(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            source = pathlib.Path(root, "src/router")
            source.mkdir(parents=True)
            (source / "preexisting.py").write_text("dirty before route\n", encoding="utf-8")
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n", encoding="utf-8",
            )
            decision = route.materialize_route(
                route.RouteInvocation(LOCAL_BASE, "issue-1", "scheduled", root),
            )
            (source / "main.py").write_text("built\n", encoding="utf-8")
            finalized = route.finalize_route(root, decision)
            self.assertEqual("passed", finalized["runtime_tripwire"]["status"])
            self.assertEqual(["src/router/main.py"], finalized["runtime_tripwire"]["changed_paths"])

    def test_materialization_requires_git_and_recovers_an_interrupted_pair_write(self):
        with tempfile.TemporaryDirectory() as root:
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n", encoding="utf-8",
            )
            invocation = route.RouteInvocation(LOCAL_BASE, "issue-1", "scheduled", root)
            with self.assertRaisesRegex(route.RouteRefused, "Git baseline"):
                route.materialize_route(invocation)
            self.assertFalse((tasks / "route-decision.md").exists())

            self.init_repo(root)
            original = route._atomic_write
            calls = 0
            def interrupt(path, content):
                nonlocal calls
                calls += 1
                if calls == 3:
                    raise OSError("injected decision write failure")
                original(path, content)
            route._atomic_write = interrupt
            try:
                with self.assertRaisesRegex(OSError, "injected"):
                    route.materialize_route(invocation)
            finally:
                route._atomic_write = original
            self.assertTrue((tasks / ".route-transaction.json").exists())
            self.assertNotIn(
                "<!-- route-lane:begin -->",
                (tasks / "todo.md").read_text(encoding="utf-8"),
            )
            route._recover_route_state(root)
            self.assertFalse((tasks / ".route-transaction.json").exists())
            self.assertTrue((tasks / "route-decision.md").exists())

    def test_completed_reviews_cannot_skip_a_pending_tripwire(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            decision = self.decide()
            (tasks / "todo.md").write_text(
                route._merge_lane("", decision, route._render_playbook(decision)), encoding="utf-8",
            )
            route._write_route_state(root, decision, (tasks / "todo.md").read_text(encoding="utf-8"))
            review = {
                "outcomes": {"code-reviewer": "completed", "critic": "completed"},
                "independently_dispatched": True,
                "unresolved_findings": [],
            }
            finalized = route.finalize_reviewers(root, decision, review)
            self.assertEqual("gated-at-plan-and-pre-push", finalized["autonomy"])

    def test_audit_file_tampering_cannot_change_canonical_policy(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            (tasks / "todo.md").write_text(
                "- [ ] Route it <!-- task-id: issue-1 -->\n", encoding="utf-8",
            )
            decision = route.materialize_route(
                route.RouteInvocation(LOCAL_BASE, "issue-1", "scheduled", root),
            )
            record_path = tasks / "route-decision.md"
            tampered = record_path.read_text(encoding="utf-8").replace(
                '"declared_paths": [\n    "src/router/"\n  ]',
                '"declared_paths": [\n    "src/"\n  ]',
            )
            record_path.write_text(tampered, encoding="utf-8")
            pathlib.Path(root, "src/payments").mkdir(parents=True)
            pathlib.Path(root, "src/payments/main.py").write_text("unsafe\n", encoding="utf-8")
            finalized = route.finalize_route(root, decision)
            self.assertEqual(["src/router/"], finalized["declared_paths"])
            self.assertEqual("gated-at-plan-and-pre-push", finalized["autonomy"])

    def test_worktree_fingerprint_does_not_follow_repository_symlinks(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            external = pathlib.Path(outside, "secret.txt")
            external.write_text("first secret\n", encoding="utf-8")
            link = pathlib.Path(root, "link")
            link.symlink_to(external)
            before = route._fingerprint(root, "link")
            external.write_text("second secret\n", encoding="utf-8")
            after = route._fingerprint(root, "link")
            self.assertEqual(before, after)
            self.assertTrue(before.startswith("symlink:"))

    def test_public_finalize_derives_changed_paths_from_recorded_git_baseline(self):
        with tempfile.TemporaryDirectory() as root:
            subprocess.run(["git", "init", "-q", root], check=True)
            subprocess.run(["git", "-C", root, "config", "user.email", "route@example.test"], check=True)
            subprocess.run(["git", "-C", root, "config", "user.name", "Route Test"], check=True)
            source = pathlib.Path(root, "src/router")
            source.mkdir(parents=True)
            (source / "main.py").write_text("before\n", encoding="utf-8")
            subprocess.run(["git", "-C", root, "add", "."], check=True)
            subprocess.run(["git", "-C", root, "commit", "-qm", "baseline"], check=True)
            decision = self.decide()
            decision["baseline_revision"] = subprocess.check_output(
                ["git", "-C", root, "rev-parse", "HEAD"], text=True
            ).strip()
            tasks = pathlib.Path(root, "tasks")
            tasks.mkdir()
            route._write_route_state(root, decision, "")
            (source / "main.py").write_text("after\n", encoding="utf-8")
            pathlib.Path(root, "src/router/new.py").write_text("new\n", encoding="utf-8")
            finalized = route.finalize_route(root, decision)
            self.assertEqual("passed", finalized["runtime_tripwire"]["status"])
            self.assertEqual(["src/router/main.py", "src/router/new.py"], finalized["runtime_tripwire"]["changed_paths"])

    def test_public_finalizer_refuses_to_bootstrap_unmaterialized_state(self):
        with tempfile.TemporaryDirectory() as root:
            self.init_repo(root)
            with self.assertRaisesRegex(route.RouteRefused, "canonical route state is absent"):
                route.finalize_route(root, self.decide())

    def test_pure_policy_requires_explicit_project_discovery_result(self):
        with self.assertRaises(TypeError):
            route.RouteRequest(BASE, self.task(), "scheduled", self.config())

    def test_shared_tripwire_owns_declared_path_comparison(self):
        decision = self.decide()
        inside = route.check_actual_diff(decision, ["src/router/main.py"])
        outside = route.check_actual_diff(decision, ["src/router/main.py", "api/routes.py"])
        self.assertFalse(inside["overflow"])
        self.assertEqual([], inside["outside_declared_paths"])
        self.assertTrue(outside["overflow"])
        self.assertEqual(["api/routes.py"], outside["outside_declared_paths"])
        broad = dict(decision, declared_paths=["src/"], declared_radius=1)
        spread = route.check_actual_diff(broad, ["src/auth/main.py", "src/payments/main.py"])
        self.assertTrue(spread["overflow"])
        self.assertEqual(2, spread["actual_radius"])


unittest.main()
PY
