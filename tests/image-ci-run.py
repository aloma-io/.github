"""Runs the jobs of a reusable workflow locally, the way GitHub Actions would for the subset image-ci.yml uses, so the
behaviour test (tests/image-ci-local.sh) exercises the workflow's own steps as written, not a copy of them.

Supported: jobs in `needs` order (a job whose needed job did not succeed is skipped); step `if:` and `${{ }}` in
`env:` values with inputs (and their defaults), github.sha / ref / event_name / repository, steps.<id>.outputs.<k>,
secrets.<NAME>, ==, !=, &&, ||, !, (), always(), success(), failure(); GITHUB_OUTPUT; job `outputs:`. `run:` steps
run with `bash --noprofile --norc -eo pipefail`, as on a runner. `uses:` steps are not run (checkout: the caller has
already copied the fixture into the working directory; setup-node / azure login: not needed locally) and are listed
as skipped.

Usage: image-ci-run.py WORKFLOW WORKDIR CONTEXT_JSON   -> prints a JSON result on stdout
CONTEXT_JSON: {"inputs": {...}, "secrets": {...}, "github": {"sha": ..., "ref": ..., "event_name": ..., "repository": ...}}
"""
import json
import os
import re
import subprocess
import sys
import tempfile

import yaml

TOKEN = re.compile(r"'(?:[^']|'')*'|&&|\|\||==|!=|!|\(|\)|[A-Za-z_][\w.\-]*|\d+|\s+")


def load(path):
    doc = yaml.safe_load(open(path))
    if True in doc and "on" not in doc:
        doc["on"] = doc.pop(True)
    return doc


class Ctx:
    def __init__(self, doc, given):
        call = doc["on"]["workflow_call"]
        self.inputs = {k: v.get("default", "") for k, v in (call.get("inputs") or {}).items()}
        self.inputs.update(given.get("inputs", {}))
        self.secrets = given.get("secrets", {})
        self.github = given.get("github", {})
        self.steps = {}
        self.failed = False

    def lookup(self, name):
        parts = name.split(".")
        if parts[0] == "inputs":
            return self.inputs.get(".".join(parts[1:]), "")
        if parts[0] == "github":
            return self.github.get(parts[1], "")
        if parts[0] == "secrets":
            return self.secrets.get(parts[1], "")
        if parts[0] == "steps" and len(parts) == 4 and parts[2] == "outputs":
            return self.steps.get(parts[1], {}).get(parts[3], "")
        raise ValueError("unsupported context %r" % name)

    def ev(self, expr):
        out = []
        for t in TOKEN.findall(expr):
            if t.isspace():
                continue
            if t == "&&":
                out.append(" and ")
            elif t == "||":
                out.append(" or ")
            elif t == "!":
                out.append(" not ")
            elif t in ("==", "!=", "(", ")"):
                out.append(t)
            elif t.startswith("'"):
                out.append(repr(t[1:-1].replace("''", "'")))
            elif t in ("true", "false"):
                out.append(str(t == "true"))
            elif t in ("always", "success", "failure"):
                out.append("_" + t)
            elif t.isdigit():
                out.append(t)
            else:
                out.append(repr(self.lookup(t)))
        return eval("".join(out), {"__builtins__": {}, "_always": lambda: True,
                                   "_success": lambda: not self.failed, "_failure": lambda: self.failed})

    def interp(self, value):
        def one(m):
            v = self.ev(m.group(1))
            return ("true" if v else "false") if isinstance(v, bool) else str(v)
        return re.sub(r"\$\{\{(.*?)\}\}", one, str(value))

    def cond(self, s):
        c = s.get("if")
        if c is None:
            return not self.failed
        c = str(c).strip()
        m = re.fullmatch(r"\$\{\{(.*)\}\}", c)
        return bool(self.ev(m.group(1) if m else c))


def run_job(job, ctx, workdir, log):
    ctx.steps, ctx.failed = {}, False
    record = []
    for s in job.get("steps") or []:
        name = s.get("name") or s.get("id") or s.get("uses") or "step"
        if not ctx.cond(s):
            record.append({"name": name, "id": s.get("id"), "result": "skipped"})
            continue
        if "uses" in s:
            record.append({"name": name, "id": s.get("id"), "result": "skipped-uses"})
            continue
        env = dict(os.environ)
        env.update({k: ctx.interp(v) for k, v in (s.get("env") or {}).items()})
        with tempfile.NamedTemporaryFile("w", suffix=".out", delete=False) as o, \
                tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
            f.write(s["run"])
        env["GITHUB_OUTPUT"], env["GITHUB_SHA"] = o.name, str(ctx.github.get("sha", ""))
        p = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", f.name], cwd=workdir, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        log.write("### %s (exit %d)\n%s\n" % (name, p.returncode, p.stdout))
        outs = parse_outputs(open(o.name).read())
        os.unlink(o.name)
        os.unlink(f.name)
        if s.get("id"):
            ctx.steps[s["id"]] = outs
        record.append({"name": name, "id": s.get("id"), "result": "success" if p.returncode == 0 else "failure"})
        if p.returncode != 0:
            ctx.failed = True
    outputs = {k: ctx.interp(v) for k, v in (job.get("outputs") or {}).items()}
    return {"result": "failure" if ctx.failed else "success", "steps": record, "outputs": outputs}


def parse_outputs(text):
    outs, lines, i = {}, text.splitlines(), 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^([\w-]+)<<(.+)$", line)
        if m:
            key, end, buf = m.group(1), m.group(2), []
            i += 1
            while i < len(lines) and lines[i] != end:
                buf.append(lines[i])
                i += 1
            outs[key] = "\n".join(buf)
        elif "=" in line:
            k, v = line.split("=", 1)
            outs[k] = v
        i += 1
    return outs


def main():
    wf, workdir, given = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    doc = load(wf)
    ctx = Ctx(doc, given)
    results, pending = {}, dict(doc["jobs"])
    with open(os.path.join(workdir, ".image-ci-run.log"), "a") as log:
        while pending:
            ready = [n for n, j in pending.items()
                     if all(d in results for d in ([j["needs"]] if isinstance(j.get("needs"), str) else j.get("needs") or []))]
            if not ready:
                raise SystemExit("needs cycle or unknown job")
            for n in ready:
                j = pending.pop(n)
                needs = [j["needs"]] if isinstance(j.get("needs"), str) else j.get("needs") or []
                if any(results[d]["result"] != "success" for d in needs):
                    results[n] = {"result": "skipped", "steps": [], "outputs": {}}
                else:
                    results[n] = run_job(j, ctx, workdir, log)
    print(json.dumps({"jobs": results}))


if __name__ == "__main__":
    main()
