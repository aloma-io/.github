"""Structural tests for the shared image CI (image-ci.yml) and its caller stub (workflow-templates/image-ci.yml).

Run: python3 -m unittest tests/test_image_ci.py   (needs PyYAML; the GitHub runner image ships it)
IMAGE_CI_ROOT points the tests at another checkout (tests/image-ci-mutants.sh uses it).

What is asserted, and why (design: claude-code knowledge/proposals/devops/PROPOSAL-IMAGE-CI-TEMPLATE-20261104.md):
- callable only; read-only token everywhere; checkout keeps no credentials;
- the only secrets are the registry ones, declared in workflow_call, never inherited, never seen by the test job,
  and only on the login steps of the build job;
- plus one optional BUILD_SECRET, only on the build step, handed to the build ONLY as a BuildKit secret mount
  (`--secret id=<build-secret-id>,env=BUILD_SECRET`, read from the step's env by name): never a build-arg, never on a
  command line, never echoed, never on the push or digest steps; no secret given, no --secret flag (the build must
  still work); the id is checked so it cannot add options to --secret;
- build `needs` test: an image is built only after the repo's own tests pass;
- one `docker build`, tagged `sha-<full commit>` and nothing else: no `latest`, no version tag, no `git tag`, no
  retag, and an existing tag is never overwritten (the existing-tag check runs before the push);
- push only when the caller asks AND the event is a push AND the ref is main;
- the digest is an output, checked against sha256:<64 hex>;
- no `${{ }}` inside run scripts (inputs reach scripts through env only);
- job timeouts; concurrency that cancels superseded PR runs only and keeps every main commit's build;
- named runner, never ubuntu-latest.
"""
import os
import re
import unittest

import yaml

ROOT = os.environ.get("IMAGE_CI_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "image-ci.yml")
CALLER = os.path.join(ROOT, "workflow-templates", "image-ci.yml")
SHARED_REF = "aloma-io/.github/.github/workflows/image-ci.yml@main"
REGISTRY_SECRETS = {"REGISTRY_USERNAME", "REGISTRY_PASSWORD", "AZURE_CREDENTIALS"}
BUILD_SECRET = "BUILD_SECRET"
DECLARED_SECRETS = REGISTRY_SECRETS | {BUILD_SECRET}
SECRET_FLAG = 'set -- --secret "id=$BUILD_SECRET_ID,env=BUILD_SECRET"'
PUSH_GUARD = "steps.gate.outputs.push == 'true'"

FORBIDDEN_RUN = [r"\bgit\s+tag\b", r"\bgit\s+push\b", r"\bnpm\s+publish\b", r"\bgh\s+release\b", r"WEBHOOK",
                 r":latest\b", r"\bdocker\s+tag\b", r"\bimagetools\s+create\b", r"\baz\s+acr\s+import\b",
                 r"\baz\s+acr\s+build\b", r"\bcrane\s+(tag|copy|cp)\b"]
FORBIDDEN_USES = [r"docker/build-push-action", r"softprops/action-gh-release", r"actions/create-release",
                  r"github-tag-action", r"actions/upload-artifact"]


def load(path):
    with open(path) as f:
        text = f.read()
    doc = yaml.safe_load(text)
    if True in doc and "on" not in doc:  # PyYAML reads the bare key `on` as boolean True
        doc["on"] = doc.pop(True)
    return text, doc


def steps(job):
    return job.get("steps") or []


def by_id(job, sid):
    found = [s for s in steps(job) if s.get("id") == sid]
    return found[0] if found else None


def code(run):
    """A run script without its comment lines."""
    return "\n".join(l for l in run.splitlines() if not l.lstrip().startswith("#"))


def secret_refs(obj):
    return set(re.findall(r"secrets\.([A-Z_]+)", yaml.safe_dump(obj)))


class SharedWorkflow(unittest.TestCase):
    def setUp(self):
        self.text, self.doc = load(WORKFLOW)
        self.jobs = self.doc["jobs"]
        self.call = self.doc["on"]["workflow_call"]

    def test_reusable_only(self):
        self.assertEqual(list(self.doc["on"].keys()), ["workflow_call"])

    def test_inputs_and_defaults(self):
        i = self.call["inputs"]
        for name in ("image-name", "test-command"):
            self.assertIs(i[name]["required"], True, name)
        self.assertIs(i["push"]["default"], False, "push is opt-in")
        self.assertEqual(i["registry"]["default"], "aloma.azurecr.io")
        self.assertEqual(i["registry-login"]["default"], "password")
        self.assertEqual(i["timeout-minutes"]["default"], 20)

    def test_permissions_read_only(self):
        self.assertEqual(self.doc.get("permissions"), {"contents": "read"})
        for name, job in self.jobs.items():
            self.assertEqual(job.get("permissions"), {"contents": "read"}, "job %s" % name)

    def test_checkout_keeps_no_credentials(self):
        for name, job in self.jobs.items():
            co = [s for s in steps(job) if str(s.get("uses", "")).startswith("actions/checkout@")]
            self.assertEqual(len(co), 1, "job %s checks out once" % name)
            self.assertIs((co[0].get("with") or {}).get("persist-credentials"), False, name)

    def test_secrets_declared_are_the_registry_ones_and_the_build_secret(self):
        self.assertEqual(set(self.call.get("secrets", {})), DECLARED_SECRETS)
        for s in self.call["secrets"].values():
            self.assertIs(s.get("required"), False)
        self.assertNotIn("inherit", self.text)

    def test_test_job_sees_no_secret(self):
        self.assertEqual(secret_refs(self.jobs["test"]), set())

    def test_secrets_only_on_login_steps(self):
        build = self.jobs["build"]
        self.assertNotIn("env", build, "no job-level env: a secret there would reach every step")
        for s in steps(build):
            refs = secret_refs(s)
            if refs:
                self.assertIn(s.get("id"), ("login-password", "login-azure", "build"), "secret on step %r" % s.get("name"))
        self.assertEqual(secret_refs(by_id(build, "build")), {BUILD_SECRET}, "the build step sees the build secret only")
        self.assertEqual(secret_refs(by_id(build, "login-password")), {"REGISTRY_USERNAME", "REGISTRY_PASSWORD"})
        self.assertEqual(secret_refs(by_id(build, "login-azure")), {"AZURE_CREDENTIALS"})

    def test_build_secret_input(self):
        i = self.call["inputs"]["build-secret-id"]
        self.assertEqual(i["type"], "string")
        self.assertIs(i["required"], False)
        self.assertEqual(i["default"], "aloma_token")
        self.assertIs(self.call["secrets"][BUILD_SECRET]["required"], False, "a build needs no secret unless the caller has one")

    def test_build_secret_only_as_a_buildkit_secret_mount(self):
        b = by_id(self.jobs["build"], "build")
        self.assertIsNotNone(b, "the build step has id: build")
        self.assertEqual(b["env"][BUILD_SECRET], "${{ secrets.BUILD_SECRET }}")
        self.assertEqual(b["env"]["BUILD_SECRET_ID"], "${{ inputs.build-secret-id }}")
        run = code(b["run"])
        # the value is read by name from the step's env (env=BUILD_SECRET); it is expanded nowhere except the
        # emptiness check, so it is never on a command line, in a build-arg, a label, a file or the log
        allowed = ['if [ -n "$BUILD_SECRET" ]', ',env=BUILD_SECRET"']
        rest = run
        for a in allowed:
            self.assertEqual(rest.count(a), 1, a)
            rest = rest.replace(a, "")
        self.assertIsNone(re.search(r"BUILD_SECRET\b(?!_ID)", rest), "build secret used elsewhere in the build step")
        self.assertIn(SECRET_FLAG, run)
        self.assertNotRegex(run, r"src=|type=file", "the secret is never written to a file")
        for name, job in self.jobs.items():
            for s in steps(job):
                r = code(s.get("run", ""))
                self.assertNotRegex(r, r"--build-arg", "job %s step %r: no build-args (a build-arg lands in the image history)" % (name, s.get("name")))
                if s is not b:
                    self.assertNotIn(BUILD_SECRET, re.sub(r"BUILD_SECRET_ID", "", yaml.safe_dump(s)), "build secret on step %r" % s.get("name"))
                for line in r.splitlines():
                    if re.search(r"\b(echo|printf|tee|cat)\b", line):
                        self.assertNotRegex(line, r"BUILD_SECRET\b(?!_ID)", "the build secret is never printed: %r" % line)

    def test_build_secret_flag_only_when_given(self):
        run = code(by_id(self.jobs["build"], "build")["run"])
        m = re.search(r'set --\n\s*if \[ -n "\$BUILD_SECRET" \]; then\n(.*?)\n\s*fi\n', run, re.S)
        self.assertIsNotNone(m, "--secret is added only when a build secret was passed: no secret, plain build")
        self.assertIn(SECRET_FLAG, m.group(1))
        self.assertRegex(m.group(1), r'case "\$BUILD_SECRET_ID" in \'\'\|\*\[!A-Za-z0-9_.-\]\*\) .*exit 1;; esac',
                         "the id is checked: a comma in it would add options (src=...) to --secret")
        self.assertLess(m.group(1).index("case"), m.group(1).index(SECRET_FLAG))
        build_line = run[m.end():]
        self.assertRegex(build_line, r'docker build [^\n]*"\$@"', "docker build takes the flag from \"$@\"")
        self.assertEqual(run.count("--secret"), 1)

    def test_build_needs_test(self):
        self.assertEqual(self.jobs["build"].get("needs"), "test")
        self.assertEqual(set(self.jobs), {"test", "build"}, "no other job (the promotion job is not built yet)")

    def test_no_expression_inside_run_scripts(self):
        for name, job in self.jobs.items():
            for s in steps(job):
                if "run" in s:
                    self.assertNotIn("${{", s["run"], "job %s step %r: pass values through env" % (name, s.get("name")))

    def test_no_tag_moving_publish_or_release(self):
        for name, job in self.jobs.items():
            self.assertNotIn("uses", job, "job %s must not call another workflow" % name)
            for s in steps(job):
                for pat in FORBIDDEN_RUN:
                    self.assertIsNone(re.search(pat, s.get("run", ""), re.I), "job %s: %s in %r" % (name, pat, s.get("name")))
                for pat in FORBIDDEN_USES:
                    self.assertIsNone(re.search(pat, str(s.get("uses", "")), re.I), "job %s uses %s" % (name, pat))

    def test_tag_is_the_full_commit_with_prefix(self):
        meta = by_id(self.jobs["build"], "meta")
        self.assertEqual(meta["env"]["SHA"], "${{ github.sha }}")
        self.assertIn('tag=sha-$SHA', meta["run"])
        self.assertRegex(meta["run"], r"\$\{#SHA\}.*40", "the full 40-character commit, never a short one")

    def test_one_docker_build(self):
        builds = [s for s in steps(self.jobs["build"]) if re.search(r"\bdocker\s+build\b", s.get("run", ""))]
        self.assertEqual(len(builds), 1)
        self.assertIn('--tag "$IMAGE:$TAG"', builds[0]["run"])
        self.assertEqual(len(re.findall(r"--tag\b|\s-t\s", builds[0]["run"])), 1, "exactly one tag")
        self.assertEqual(self.text.count("docker build"), 1)
        for name in ("test",):
            self.assertNotRegex(yaml.safe_dump(self.jobs[name]), r"docker\s+(build|push|login)", name)

    def test_push_guarded_by_input_event_and_ref(self):
        gate = by_id(self.jobs["build"], "gate")
        env = gate["env"]
        self.assertEqual(env["WANT_PUSH"], "${{ inputs.push }}")
        self.assertEqual(env["EVENT"], "${{ github.event_name }}")
        self.assertEqual(env["REF"], "${{ github.ref }}")
        r = gate["run"].replace(" ", "")
        for part in ('"$WANT_PUSH"="true"', '"$EVENT"="push"', '"$REF"="refs/heads/main"'):
            self.assertIn(part, r)
        self.assertRegex(r, r'"\$WANT_PUSH"="true"\]&&\["\$EVENT"="push"\]&&\["\$REF"="refs/heads/main"\]')
        for sid in ("login-password", "login-azure", "acr-login", "exists", "push", "digest", "logout"):
            s = by_id(self.jobs["build"], sid)
            self.assertIsNotNone(s, sid)
            self.assertIn(PUSH_GUARD, s.get("if", ""), "step %s must be gated" % sid)
        pushes = [s for s in steps(self.jobs["build"]) if re.search(r"\bdocker\s+push\b", s.get("run", ""))]
        self.assertEqual([s.get("id") for s in pushes], ["push"])

    def test_existing_tag_is_never_overwritten(self):
        ids = [s.get("id") for s in steps(self.jobs["build"])]
        self.assertLess(ids.index("exists"), ids.index("push"))
        self.assertIn("steps.exists.outputs.exists == 'false'", by_id(self.jobs["build"], "push")["if"])
        ex = by_id(self.jobs["build"], "exists")["run"]
        self.assertIn("docker pull", ex)
        self.assertRegex(ex, r"manifest unknown|not found", "only a not-found answer counts as absent")

    def test_digest_output_checked(self):
        build = self.jobs["build"]
        outs = build["outputs"]
        self.assertEqual(outs["digest"], "${{ steps.digest.outputs.digest }}")
        self.assertEqual(outs["ref"], "${{ steps.digest.outputs.ref }}")
        dg = by_id(build, "digest")
        self.assertIn("^sha256:[0-9a-f]{64}$", dg["run"])
        # the registry's digest, as reported by the push (or by the pull of the existing tag); never a local image id,
        # which equals the manifest digest only on some image stores
        self.assertEqual(dg["env"]["PUSHED"], "${{ steps.push.outputs.digest }}")
        self.assertEqual(dg["env"]["EXISTING"], "${{ steps.exists.outputs.digest }}")
        self.assertIn("d=${PUSHED:-$EXISTING}", dg["run"])
        self.assertNotRegex(dg["run"], r"docker\s+(image\s+)?inspect|\.Id\b")
        self.assertRegex(by_id(build, "push")["run"], r"digest: \\\(sha256:")
        wouts = self.call["outputs"]
        for k in ("image", "tag", "digest", "ref"):
            self.assertEqual(wouts[k]["value"], "${{ jobs.build.outputs.%s }}" % k)

    def test_logout_always(self):
        self.assertIn("always()", by_id(self.jobs["build"], "logout")["if"])

    def test_timeouts(self):
        for name, job in self.jobs.items():
            self.assertEqual(job.get("timeout-minutes"), "${{ inputs.timeout-minutes }}", name)

    def test_named_runner(self):
        for name, job in self.jobs.items():
            self.assertEqual(job.get("runs-on"), "ubuntu-26.04", name)

    def test_concurrency(self):
        for name, job in self.jobs.items():
            c = job.get("concurrency")
            self.assertIsInstance(c, dict, name)
            for part in ("github.repository", "inputs.image-name", "github.sha", "github.ref"):
                self.assertIn(part, c["group"], name)
            self.assertIn("github.event_name == 'pull_request' && github.ref || github.sha", c["group"],
                          "%s: PRs share a group per ref; every main commit gets its own" % name)
            self.assertEqual(c["cancel-in-progress"], "${{ github.event_name == 'pull_request' }}", name)


class CallerStub(unittest.TestCase):
    def setUp(self):
        self.text, self.doc = load(CALLER)
        self.job = next(iter(self.doc["jobs"].values()))

    def test_triggers(self):
        on = self.doc["on"]
        self.assertEqual(on["push"], {"branches": ["main"]}, "push to main only, never tags")
        self.assertIn("pull_request", on)
        self.assertNotIn("schedule", on)

    def test_calls_shared_workflow(self):
        self.assertEqual(len(self.doc["jobs"]), 1)
        self.assertEqual(self.job["uses"], SHARED_REF)

    def test_push_only_from_main_pushes(self):
        self.assertEqual(self.job["with"]["push"], "${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}")

    def test_secrets_explicit_and_registry_only(self):
        sec = self.job.get("secrets")
        self.assertIsInstance(sec, dict, "secrets passed by name, never inherit")
        self.assertTrue(set(sec) <= DECLARED_SECRETS, sec)
        self.assertNotIn("inherit", self.text)

    def test_permissions_read_only(self):
        self.assertEqual(self.doc.get("permissions"), {"contents": "read"})


if __name__ == "__main__":
    unittest.main()
