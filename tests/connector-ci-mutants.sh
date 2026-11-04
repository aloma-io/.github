#!/bin/bash
# Mutation check for the connector-ci tests: each mutant breaks one asserted property of connector-ci.yml or of the
# caller stub in a scratch copy of this repo; the structural test (tests/test_connector_ci.py) or the behaviour test
# (tests/connector-ci-local.sh) must then fail. A mutant that leaves both green has survived: this script fails.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
WFR=.github/workflows/connector-ci.yml
CALLR=workflow-templates/connector-ci.yml
survived=0

# name | file | python expression applied to the file text s (must change it)
MUTANTS=$(cat <<'EOF'
write-permission|W|s.replace("contents: read", "contents: write", 1)
secrets-used|W|s.replace("run: yarn test", "run: yarn test\n        env:\n          T: ${{ secrets.WEBHOOK_URL }}", 1)
webhook-step|W|s.replace("run: yarn test", "run: yarn test && curl -X POST \"$URL\"", 1)
tag-step|W|s.replace("run: yarn build", "run: yarn build && git tag v9.9.9", 1)
no-frozen-lockfile|W|s.replace("yarn install --frozen-lockfile", "yarn install", 1)
no-test-step|W|s.replace("      - name: Test\n        run: yarn test\n", "", 1)
no-build-step|W|s.replace("      - name: Build\n        run: yarn build\n", "", 1)
no-timeout|W|s.replace("    timeout-minutes: ${{ inputs.timeout-minutes }}\n", "", 1)
no-concurrency|W|s.replace("    concurrency:\n", "    xconcurrency:\n", 1)
cancel-main-runs|W|s.replace("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", "cancel-in-progress: true", 1)
mutants-on-push|W|s.replace("inputs.run-mutants && (", "inputs.run-mutants || (", 1)
latest-runner|W|s.replace("runs-on: ubuntu-26.04", "runs-on: ubuntu-latest", 1)
keep-credentials|W|s.replace("persist-credentials: false", "persist-credentials: true", 1)
caller-no-main-push|C|s.replace("branches: [main]", "branches: [dev]", 1)
caller-no-pr|C|s.replace("  pull_request:\n", "", 1)
caller-inherit-secrets|C|s.replace("    with:\n", "    secrets: inherit\n    with:\n", 1)
caller-cron|C|s.replace("  workflow_dispatch:\n", "  schedule:\n    - cron: '0 2 * * *'\n  workflow_dispatch:\n", 1)
caller-write|C|s.replace("contents: read", "contents: write", 1)
caller-wrong-ref|C|s.replace("connector-ci.yml@main", "docker-build-push.yml@main", 1)
EOF
)

while IFS='|' read -r name which expr; do
  [ -n "$name" ] || continue
  scratch=$(mktemp -d)
  cp -R "$ROOT/.github" "$ROOT/workflow-templates" "$scratch/"
  target=$([ "$which" = W ] && echo "$scratch/$WFR" || echo "$scratch/$CALLR")
  if ! python3 - "$target" "$expr" <<'PY'
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read()
t = eval(expr)
if t == s:
    sys.exit("mutant did not change the file")
open(p, "w").write(t)
PY
  then echo "ERROR mutant $name did not apply"; survived=1; rm -rf "$scratch"; continue; fi
  CONNECTOR_CI_ROOT=$scratch python3 -m unittest -q "$HERE/test_connector_ci.py" >/dev/null 2>&1; s=$?
  CONNECTOR_CI_ROOT=$scratch bash "$HERE/connector-ci-local.sh" >/dev/null 2>&1; b=$?
  if [ $s != 0 ] || [ $b != 0 ]; then
    echo "killed    $name (structural=$s behaviour=$b)"
  else
    echo "SURVIVED  $name"; survived=1
  fi
  rm -rf "$scratch"
done <<< "$MUTANTS"
[ $survived = 0 ] && echo "ALL MUTANTS KILLED" || echo "MUTANTS SURVIVED"
exit $survived
