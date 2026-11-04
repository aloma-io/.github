"""Structural tests for the shared connector CI (connector-ci.yml) and its caller stub.

Run: python3 -m unittest tests/test_connector_ci.py   (needs PyYAML; the GitHub runner image ships it)
CONNECTOR_CI_ROOT points the tests at another checkout (tests/connector-ci-mutants.sh uses it).

What is asserted, and why (contract: claude-code-dev knowledge/reference/CONNECTOR-TEST-JOB-CONTRACT.md):
- the workflow is test-only: read-only token, no secrets, no tag / publish / push / webhook step;
- it runs `yarn install --frozen-lockfile`, `yarn build`, `yarn test`, in that order;
- a job timeout and a concurrency group exist;
- mutants never run on push or pull_request;
- the caller runs on push to main and on pull_request, passes no secrets and calls the shared workflow.
"""
import os
import re
import unittest

import yaml

ROOT = os.environ.get("CONNECTOR_CI_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "connector-ci.yml")
CALLER = os.path.join(ROOT, "workflow-templates", "connector-ci.yml")
SHARED_REF = "aloma-io/.github/.github/workflows/connector-ci.yml@main"

# Anything that could release, publish or reach the deploy webhook. Matched against run scripts and `uses:`.
FORBIDDEN_RUN = [
    r"\bgit\s+tag\b", r"\bgit\s+push\b", r"\bnpm\s+publish\b", r"\byarn\s+publish\b", r"\bdocker\s+push\b",
    r"\bdocker\s+login\b", r"\bgh\s+release\b", r"WEBHOOK", r"\bcurl\b", r"\bwget\b",
]
FORBIDDEN_USES = [r"docker/login-action", r"docker/build-push-action", r"softprops/action-gh-release",
                  r"actions/create-release", r"anothrNick/github-tag-action", r"mathieudutour/github-tag-action"]


def load(path):
    with open(path) as f:
        text = f.read()
    doc = yaml.safe_load(text)
    # PyYAML reads the bare key `on` as boolean True
    if True in doc and "on" not in doc:
        doc["on"] = doc.pop(True)
    return text, doc


def steps(job):
    return job.get("steps") or []


def runs(job):
    return [s["run"] for s in steps(job) if "run" in s]


class SharedWorkflow(unittest.TestCase):
    def setUp(self):
        self.text, self.doc = load(WORKFLOW)
        self.jobs = self.doc["jobs"]

    def test_reusable_only(self):
        self.assertEqual(list(self.doc["on"].keys()), ["workflow_call"], "callable only, never triggered by itself")

    def test_inputs_and_defaults(self):
        inputs = self.doc["on"]["workflow_call"]["inputs"]
        self.assertEqual(inputs["node-versions"]["default"], '["22"]')
        self.assertEqual(inputs["timeout-minutes"]["default"], 15)
        self.assertIs(inputs["run-mutants"]["default"], False)

    def test_takes_no_secrets(self):
        self.assertNotIn("secrets", self.doc["on"]["workflow_call"], "workflow_call must declare no secrets")
        self.assertNotIn("secrets.", self.text, "no reference to the secrets context")
        self.assertNotIn("secrets: inherit", self.text)

    def test_permissions_read_only(self):
        self.assertEqual(self.doc.get("permissions"), {"contents": "read"}, "workflow-level permissions")
        for name, job in self.jobs.items():
            self.assertEqual(job.get("permissions"), {"contents": "read"}, "job %s permissions" % name)

    def test_checkout_keeps_no_credentials(self):
        for name, job in self.jobs.items():
            for s in steps(job):
                if str(s.get("uses", "")).startswith("actions/checkout@"):
                    self.assertIs((s.get("with") or {}).get("persist-credentials"), False, "job %s checkout" % name)

    def test_no_tag_publish_or_webhook(self):
        for name, job in self.jobs.items():
            for r in runs(job):
                for pat in FORBIDDEN_RUN:
                    self.assertIsNone(re.search(pat, r, re.I), "job %s runs forbidden %s: %r" % (name, pat, r))
            for s in steps(job):
                for pat in FORBIDDEN_USES:
                    self.assertIsNone(re.search(pat, str(s.get("uses", "")), re.I), "job %s uses %s" % (name, pat))
            self.assertNotIn("uses", job, "job %s must not call another workflow" % name)

    def test_install_build_test_in_order(self):
        cmds = [r.strip() for r in runs(self.jobs["test"])]
        self.assertEqual(cmds, ["yarn install --frozen-lockfile", "yarn build", "yarn test"])

    def test_node_matrix_from_input(self):
        job = self.jobs["test"]
        self.assertEqual(job["strategy"]["matrix"]["node"], "${{ fromJSON(inputs.node-versions) }}")
        self.assertIs(job["strategy"]["fail-fast"], False)
        setup = [s for s in steps(job) if str(s.get("uses", "")).startswith("actions/setup-node@")]
        self.assertEqual(len(setup), 1)
        self.assertEqual(setup[0]["with"]["node-version"], "${{ matrix.node }}")
        self.assertEqual(setup[0]["with"]["cache"], "yarn")

    def test_timeout_present(self):
        for name, job in self.jobs.items():
            self.assertEqual(job.get("timeout-minutes"), "${{ inputs.timeout-minutes }}", "job %s timeout" % name)

    def test_named_runner(self):
        for name, job in self.jobs.items():
            self.assertEqual(job.get("runs-on"), "ubuntu-26.04", "job %s: name the image, never ubuntu-latest" % name)

    def test_concurrency_per_ref_and_node(self):
        c = self.jobs["test"].get("concurrency")
        self.assertIsInstance(c, dict, "test job needs a concurrency group")
        for part in ("github.repository", "github.ref", "matrix.node", "github.event_name"):
            self.assertIn(part, c["group"])
        self.assertEqual(c["cancel-in-progress"], "${{ github.event_name == 'pull_request' }}",
                         "cancel superseded PR runs only; every main commit keeps its result")

    def test_mutants_never_on_push_or_pr(self):
        job = self.jobs["mutants"]
        cond = job.get("if", "")
        self.assertIn("inputs.run-mutants", cond)
        self.assertIn("github.event_name == 'workflow_dispatch'", cond)
        for ev in ("'push'", "'pull_request'"):
            self.assertNotIn(ev, cond)
        # the guard must be an AND with the event check, not an OR that lets run-mutants alone through
        self.assertRegex(cond.replace(" ", ""), r"inputs\.run-mutants&&\(")
        self.assertEqual(job.get("needs"), "test")


class CallerStub(unittest.TestCase):
    def setUp(self):
        self.text, self.doc = load(CALLER)

    def test_triggers(self):
        on = self.doc["on"]
        self.assertEqual(on["push"], {"branches": ["main"]}, "push to main only")
        self.assertIn("pull_request", on)
        self.assertNotIn("schedule", on, "no cron: nightly mutants run on the Mac (Actions cap)")
        self.assertEqual(set(on), {"push", "pull_request", "workflow_dispatch"})
        self.assertIs(on["workflow_dispatch"]["inputs"]["run-mutants"]["default"], False)

    def test_calls_shared_workflow_without_secrets(self):
        jobs = self.doc["jobs"]
        self.assertEqual(len(jobs), 1)
        job = next(iter(jobs.values()))
        self.assertEqual(job["uses"], SHARED_REF)
        self.assertNotIn("secrets", job)
        self.assertNotIn("secrets", self.text, "the caller passes and names no secrets")

    def test_permissions_read_only(self):
        self.assertEqual(self.doc.get("permissions"), {"contents": "read"})

    def test_passes_node_versions(self):
        job = next(iter(self.doc["jobs"].values()))
        self.assertIn("node-versions", job["with"])


if __name__ == "__main__":
    unittest.main()
