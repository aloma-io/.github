"""PLAT-140: the shared CI workflows warn (or fail) when the calling repo names a floating runner label (-latest).

Run: python3 -m unittest tests/test_runner_label_guard.py   (needs PyYAML)
RUNNER_GUARD_ROOT points at another checkout (tests/runner-label-guard-mutants.sh uses it).

Behaviour, not text: the guard step's own `run` script is taken out of connector-ci.yml and image-ci.yml and executed
by bash against fixture .github/workflows folders.
"""
import os
import subprocess
import tempfile
import unittest

import yaml

ROOT = os.environ.get("RUNNER_GUARD_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEP = "Runner label guard"
FILES = ("connector-ci.yml", "image-ci.yml")


def load(name):
    with open(os.path.join(ROOT, ".github", "workflows", name)) as f:
        doc = yaml.safe_load(f)
    if True in doc and "on" not in doc:
        doc["on"] = doc.pop(True)
    return doc


def guard_step(doc):
    steps = doc["jobs"]["test"]["steps"]
    found = [(i, s) for i, s in enumerate(steps) if s.get("name") == STEP]
    return steps, found


def run_guard(name, workflow_text, fail):
    doc = load(name)
    _, found = guard_step(doc)
    script = found[0][1]["run"]
    with tempfile.TemporaryDirectory() as d:
        if workflow_text is not None:
            os.makedirs(os.path.join(d, ".github", "workflows"))
            with open(os.path.join(d, ".github", "workflows", "x.yml"), "w") as f:
                f.write(workflow_text)
        env = dict(os.environ, FAIL_ON_FLOATING="true" if fail else "false")
        p = subprocess.run(["bash", "-e", "-c", script], cwd=d, env=env, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


class GuardTests(unittest.TestCase):
    def each(self):
        for n in FILES:
            with self.subTest(workflow=n):
                yield n

    def test_step_exists_once_after_checkout_in_test_job(self):
        for n in self.each():
            steps, found = guard_step(load(n))
            self.assertEqual(len(found), 1)
            i, step = found[0]
            self.assertTrue(any("actions/checkout" in s.get("uses", "") for s in steps[:i]))
            self.assertIn("${{ github.workspace }}", step.get("working-directory", ""))

    def test_input_defaults_to_warn_only(self):
        for n in self.each():
            inp = load(n)["on"]["workflow_call"]["inputs"]["fail-on-floating-runner"]
            self.assertEqual(inp["type"], "boolean")
            self.assertIs(inp["default"], False)
            step = guard_step(load(n))[1][0][1]
            self.assertIn("inputs.fail-on-floating-runner", str(step["env"]))

    def test_pinned_labels_pass_silently(self):
        for n in self.each():
            rc, out = run_guard(n, "jobs:\n  a:\n    runs-on: ubuntu-26.04\n", fail=True)
            self.assertEqual(rc, 0, out)
            self.assertNotIn("floating", out)

    def test_no_workflows_folder_passes(self):
        for n in self.each():
            self.assertEqual(run_guard(n, None, fail=True)[0], 0)

    def test_latest_warns_and_passes_when_not_failing(self):
        for label in ("ubuntu-latest", "macos-latest", "windows-latest"):
            for n in self.each():
                rc, out = run_guard(n, "jobs:\n  a:\n    runs-on: %s\n" % label, fail=False)
                self.assertEqual(rc, 0, out)
                self.assertIn("::warning::floating runner label", out)
                self.assertIn("x.yml:3", out)

    def test_latest_fails_when_asked(self):
        for n in self.each():
            rc, out = run_guard(n, "jobs:\n  a:\n    runs-on: ubuntu-latest\n", fail=True)
            self.assertEqual(rc, 1, out)

    def test_list_and_matrix_forms_are_caught(self):
        for text in ("jobs:\n  a:\n    runs-on: [ubuntu-latest, x]\n",
                     "jobs:\n  a:\n    strategy:\n      matrix:\n        os: [ubuntu-26.04, ubuntu-latest]\n"):
            for n in self.each():
                self.assertEqual(run_guard(n, text, fail=True)[0], 1)

    def test_comments_are_not_hits(self):
        for n in self.each():
            rc, out = run_guard(n, "# was ubuntu-latest\njobs:\n  a:\n    # ubuntu-latest\n    runs-on: ubuntu-26.04\n", fail=True)
            self.assertEqual(rc, 0, out)


CANARY = os.path.join(ROOT, "workflow-templates", "runner-canary.yml")


class CanaryTemplate(unittest.TestCase):
    """PLAT-140 / row 2.046: the opt-in weekly canary a repo copies when its pin is below the newest image. It only tests."""

    def setUp(self):
        with open(CANARY) as f:
            self.text = f.read()
        self.doc = yaml.safe_load(self.text)
        self.doc["on"] = self.doc.pop(True, self.doc.get("on"))
        self.job = self.doc["jobs"]["canary"]

    def test_runs_weekly_and_on_demand_only(self):
        on = self.doc["on"]
        self.assertEqual(set(on), {"schedule", "workflow_dispatch"})
        self.assertEqual(len(on["schedule"]), 1)
        minute, hour, dom, mon, dow = on["schedule"][0]["cron"].split()
        self.assertEqual((dom, mon), ("*", "*"))
        self.assertTrue(dow.isdigit())            # one weekday, never daily

    def test_names_the_image_and_is_read_only(self):
        self.assertRegex(self.job["runs-on"], r"^(ubuntu|windows|macos)-\d")
        self.assertEqual(self.doc["permissions"], {"contents": "read"})
        self.assertIn("timeout-minutes", self.job)

    def test_it_can_not_release_or_publish(self):
        self.assertNotIn("secrets", self.text.lower().replace("no secrets", ""))
        for bad in ("git tag", "git push", "npm publish", "yarn publish", "docker push", "docker login", "gh release", "curl", "WEBHOOK"):
            self.assertNotIn(bad, self.text)
        self.assertNotIn("uses", {k: 1 for k in self.job})          # does not call another workflow

    def test_guard_finds_no_floating_label_in_it(self):
        rc, out = run_guard("connector-ci.yml", self.text, fail=True)
        self.assertEqual(rc, 0, out)


if __name__ == "__main__":
    unittest.main()
