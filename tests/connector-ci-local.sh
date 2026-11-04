#!/bin/bash
# Behaviour test for .github/workflows/connector-ci.yml: runs the `run:` steps of its `test` job, exactly as written in
# the workflow, against each fixture connector under tests/fixtures/, in a scratch copy, and checks the result:
#   connector-green       must pass, and its test script must have run (it writes test-ran.marker)
#   connector-red-test    must fail (yarn test exits 1)
#   connector-red-build   must fail (yarn build exits 2)
#   connector-stale-lock  must fail (package.json names a dependency yarn.lock lacks: --frozen-lockfile refuses)
# Needs node, yarn (1.x) and python3 with PyYAML. No network: the fixtures have no registry dependencies.
# CONNECTOR_CI_ROOT points it at another checkout (tests/connector-ci-mutants.sh uses it).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${CONNECTOR_CI_ROOT:-$(dirname "$HERE")}
WF="$ROOT/.github/workflows/connector-ci.yml"
FIX="$HERE/fixtures"
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

# The test job's run steps, one per NUL-terminated record, in order.
extract() {
  python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for s in doc["jobs"]["test"].get("steps") or []:
    if "run" in s:
        sys.stdout.write(s["run"] + "\0")
PY
}

run_fixture() {  # $1 fixture name, $2 scratch dir; returns the exit code of the first failing step (0 if none)
  local cmd
  cp -R "$FIX/$1/." "$2/"
  while IFS= read -r -d '' cmd; do
    (cd "$2" && bash -e -c "$cmd") >>"$2/.log" 2>&1 || return $?
  done < <(extract)
  return 0
}

steps=$(extract | tr '\0' '\n')
[ -n "$steps" ] || { echo "FAIL  no run steps found in $WF"; exit 1; }

for f in connector-green connector-red-test connector-red-build connector-stale-lock; do
  dir=$(mktemp -d)
  run_fixture "$f" "$dir"; rc=$?
  case $f in
    connector-green)
      [ "$rc" = 0 ] && ok "$f passes" || bad "$f failed with $rc: $(tail -3 "$dir/.log")"
      [ -f "$dir/test-ran.marker" ] && ok "$f: the test script ran" || bad "$f: the test script never ran" ;;
    *)
      [ "$rc" != 0 ] && ok "$f fails (exit $rc)" || bad "$f passed; it must fail" ;;
  esac
  rm -rf "$dir"
done
[ $fail = 0 ] && echo "ALL PASSED" || echo "FAILED"
exit $fail
