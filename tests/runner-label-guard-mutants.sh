#!/bin/bash
# Mutation check for tests/test_runner_label_guard.py: each mutant breaks the PLAT-140 guard step in a scratch copy of
# this repo's workflows; the test must then fail. A surviving mutant makes this script exit 1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
survived=0
MUTANTS=$(cat <<'EOT'
never-fails|s.replace('exit 1; fi', 'exit 0; fi', 1)
always-fails|s.replace('exit 1; fi', 'exit 1; fi\n            exit 1', 1)
ignores-macos|s.replace('(ubuntu|windows|macos)', '(ubuntu|windows)', 1)
ignores-comments-rule|s.replace("'^[^#]*", "'", 1)
no-warning|s.replace('::warning::floating runner label: $l', 'floating $l', 1)
default-fails|s.replace("(PLAT-140).'\n        type: boolean\n        required: false\n        default: false", "(PLAT-140).'\n        type: boolean\n        required: false\n        default: true", 1)
no-filename|s.replace('grep -nHE', 'grep -nE', 1)
step-removed|s.replace('- name: Runner label guard', '- name: Something else', 1)
EOT
)
for f in connector-ci.yml image-ci.yml; do
  while IFS='|' read -r name expr; do
    [ -n "$name" ] || continue
    scratch=$(mktemp -d); cp -R "$ROOT/.github" "$ROOT/tests" "$scratch/"
    python3 - "$scratch/.github/workflows/$f" "$expr" <<'PY' || { echo "mutant $name does not apply to $f"; continue; }
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read(); t = eval(expr)
if t == s: sys.exit(1)
open(p, "w").write(t)
PY
    if RUNNER_GUARD_ROOT="$scratch" python3 -m unittest "$ROOT/tests/test_runner_label_guard.py" >/dev/null 2>&1; then
      echo "SURVIVED: $name on $f"; survived=1
    else echo "caught: $name on $f"; fi
    rm -rf "$scratch"
  done <<< "$MUTANTS"
done

# the canary template
CAN=$(cat <<'EOT'
daily-cron|s.replace("'17 3 * * 1'", "'17 3 * * *'", 1)
two-crons|s.replace("  workflow_dispatch:", "    - cron: '5 3 * * 3'\n  workflow_dispatch:", 1)
push-trigger|s.replace("  workflow_dispatch:", "  push:\n  workflow_dispatch:", 1)
floating-label|s.replace("runs-on: ubuntu-26.04", "runs-on: ubuntu-latest", 1)
write-token|s.replace("contents: read", "contents: write", 1)
no-timeout|s.replace("    timeout-minutes: 20\n", "", 1)
publishes|s.replace("exit 1\n", "exit 1 && npm publish\n", 1)
EOT
)
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  scratch=$(mktemp -d); cp -R "$ROOT/.github" "$ROOT/tests" "$ROOT/workflow-templates" "$scratch/"
  python3 - "$scratch/workflow-templates/runner-canary.yml" "$expr" <<'PY' || { echo "canary mutant $name does not apply"; survived=1; continue; }
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read(); t = eval(expr)
if t == s: sys.exit(1)
open(p, "w").write(t)
PY
  if RUNNER_GUARD_ROOT="$scratch" python3 -m unittest "$ROOT/tests/test_runner_label_guard.py" >/dev/null 2>&1; then
    echo "SURVIVED: canary $name"; survived=1
  else echo "caught: canary $name"; fi
  rm -rf "$scratch"
done <<< "$CAN"
exit $survived
