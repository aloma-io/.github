#!/bin/bash
# Mutation check for the image-ci tests: each mutant breaks one asserted property of image-ci.yml or of the caller stub
# in a scratch copy of this repo; the structural test (tests/test_image_ci.py) or, when that stays green, the behaviour
# test (tests/image-ci-local.sh, Docker + a throwaway local registry) must fail. A mutant that leaves both green has
# survived: this script fails.
# Second pass (build secret): the mutants below are ALSO run against the behaviour test alone, whatever the structural
# test says, so the Docker test is proven to catch a leaked, echoed, build-arg or dropped build secret by itself.
# BEHAVIOUR_BUILDX needs docker buildx (BuildKit secret mounts): skipped without it, unless IMAGE_CI_REQUIRE_BUILDX=1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
WFR=.github/workflows/image-ci.yml
CALLR=workflow-templates/image-ci.yml
survived=0

# name | file (W workflow, C caller) | python expression applied to the file text s (must change it)
MUTANTS=$(cat <<'EOF'
write-permission|W|s.replace("contents: read", "contents: write", 1)
test-job-secret|W|s.replace("          TEST_COMMAND: ${{ inputs.test-command }}", "          TEST_COMMAND: ${{ inputs.test-command }}\n          T: ${{ secrets.REGISTRY_PASSWORD }}", 1)
extra-secret|W|s.replace("    secrets:\n", "    secrets:\n      PAT:\n        required: false\n", 1)
secret-on-build-step|W|s.replace("          DOCKERFILE: ${{ inputs.dockerfile }}", "          DOCKERFILE: ${{ inputs.dockerfile }}\n          P: ${{ secrets.REGISTRY_PASSWORD }}", 1)
build-no-needs|W|s.replace("    needs: test\n", "", 1)
gate-no-event|W|s.replace('[ "$EVENT" = "push" ] && ', "", 1)
gate-no-ref|W|s.replace(' && [ "$REF" = "refs/heads/main" ]', "", 1)
gate-or|W|s.replace('[ "$WANT_PUSH" = "true" ] && [ "$EVENT"', '[ "$WANT_PUSH" = "true" ] || [ "$EVENT"', 1)
push-ungated|W|s.replace("if: steps.gate.outputs.push == 'true' && steps.exists.outputs.exists == 'false'", "if: steps.exists.outputs.exists != 'true'", 1)
overwrite-existing-tag|W|s.replace('echo "exists=true" >> "$GITHUB_OUTPUT"', 'echo "exists=false" >> "$GITHUB_OUTPUT"', 1)
latest-tag|W|s.replace('out=$(docker push "$IMAGE:$TAG" 2>&1)', 'docker tag "$IMAGE:$TAG" "$IMAGE:latest"; out=$(docker push "$IMAGE:$TAG" 2>&1)', 1)
short-sha-tag|W|s.replace('echo "tag=sha-$SHA"', 'echo "tag=${SHA:0:7}"', 1)
no-digest-check|W|s.replace("          printf '%s' \"$d\" | grep -Eq '^sha256:[0-9a-f]{64}$' || { echo \"::error::no valid digest for $IMAGE:$TAG ('$d')\"; exit 1; }\n", "", 1)
digest-from-local-id|W|s.replace("d=${PUSHED:-$EXISTING}", "d=$(docker image inspect --format '{{.Id}}' \"$IMAGE:$TAG\")", 1)
no-digest-output|W|s.replace("      digest: ${{ steps.digest.outputs.digest }}\n", "", 1)
no-timeout|W|s.replace("    timeout-minutes: ${{ inputs.timeout-minutes }}\n", "", 1)
no-concurrency|W|s.replace("    concurrency:\n", "    xconcurrency:\n", 1)
cancel-main-runs|W|s.replace("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", "cancel-in-progress: true", 1)
main-shares-group|W|s.replace("github.event_name == 'pull_request' && github.ref || github.sha", "github.ref", 1)
latest-runner|W|s.replace("runs-on: ubuntu-26.04", "runs-on: ubuntu-latest", 1)
keep-credentials|W|s.replace("persist-credentials: false", "persist-credentials: true", 1)
expression-in-run|W|s.replace('run: bash -e -c "$TEST_COMMAND"', "run: ${{ inputs.test-command }}", 1)
test-not-run|W|s.replace('run: bash -e -c "$TEST_COMMAND"', "run: echo skipped", 1)
prepare-skipped|W|s.replace("if: inputs.prepare-command != ''", "if: inputs.prepare-command == ''", 1)
logout-not-always|W|s.replace("if: always() && steps.gate.outputs.push == 'true'", "if: steps.gate.outputs.push == 'true'", 1)
push-default-true|W|s.replace("        type: boolean\n        required: false\n        default: false", "        type: boolean\n        required: false\n        default: true", 1)
build-secret-as-build-arg|W|s.replace('set -- --secret "id=$BUILD_SECRET_ID,env=BUILD_SECRET"', 'set -- --build-arg "ALOMA_TOKEN=$BUILD_SECRET"', 1)
build-secret-on-command-line|W|s.replace('set -- --secret "id=$BUILD_SECRET_ID,env=BUILD_SECRET"', 'export BS=$BUILD_SECRET; set -- --secret "id=$BUILD_SECRET_ID,env=BS"', 1)
build-secret-echoed|W|s.replace('            set -- --secret "id=', '            echo "build secret: $BUILD_SECRET"\n            set -- --secret "id=', 1)
build-secret-leaked-label|W|s.replace('set -- --secret "id=$BUILD_SECRET_ID,env=BUILD_SECRET"', 'set -- --secret "id=$BUILD_SECRET_ID,env=BUILD_SECRET" --label "build.secret=$BUILD_SECRET"', 1)
build-secret-leaked-context|W|s.replace('            set -- --secret "id=', '            printf %s "$BUILD_SECRET" > "${CONTEXT%/}/leak.txt"\n            set -- --secret "id=', 1)
build-secret-always-passed|W|s.replace('if [ -n "$BUILD_SECRET" ]; then', 'if true; then', 1)
build-secret-id-unchecked|W|s.replace("""            case "$BUILD_SECRET_ID" in ''|*[!A-Za-z0-9_.-]*) echo "::error::bad build-secret-id '$BUILD_SECRET_ID'"; exit 1;; esac\n""", "", 1)
build-secret-not-passed|W|s.replace('docker build --force-rm --label "org.opencontainers.image.revision=$SHA" "$@"', 'docker build --force-rm --label "org.opencontainers.image.revision=$SHA"', 1)
build-secret-required|W|s.replace("      BUILD_SECRET:\n        description: 'Optional build-time secret, given to the image build only as a BuildKit secret mount (id: build-secret-id)'\n        required: false", "      BUILD_SECRET:\n        description: 'x'\n        required: true", 1)
build-secret-on-prepare|W|s.replace("          PREPARE_COMMAND: ${{ inputs.prepare-command }}", "          PREPARE_COMMAND: ${{ inputs.prepare-command }}\n          BUILD_SECRET: ${{ secrets.BUILD_SECRET }}", 1)
build-secret-on-push|W|s.replace("        if: steps.gate.outputs.push == 'true' && steps.exists.outputs.exists == 'false'\n        env:\n", "        if: steps.gate.outputs.push == 'true' && steps.exists.outputs.exists == 'false'\n        env:\n          BUILD_SECRET: ${{ secrets.BUILD_SECRET }}\n", 1)
build-secret-in-test-job|W|s.replace("          TEST_COMMAND: ${{ inputs.test-command }}", "          TEST_COMMAND: ${{ inputs.test-command }}\n          BUILD_SECRET: ${{ secrets.BUILD_SECRET }}", 1)
build-secret-default-id|W|s.replace("        default: 'aloma_token'", "        default: 'token'", 1)
caller-inherit-secrets|C|s.replace("    secrets:\n      REGISTRY_USERNAME: ${{ secrets.AZURE_USER }}\n      REGISTRY_PASSWORD: ${{ secrets.AZURE_PASS }}\n", "    secrets: inherit\n", 1)
caller-extra-secret|C|s.replace("      REGISTRY_PASSWORD: ${{ secrets.AZURE_PASS }}\n", "      REGISTRY_PASSWORD: ${{ secrets.AZURE_PASS }}\n      PAT: ${{ secrets.PAT }}\n", 1)
caller-push-always|C|s.replace("push: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}", "push: true", 1)
caller-on-tags|C|s.replace("    branches: [main]", "    branches: [main]\n    tags: ['*']", 1)
caller-no-pr|C|s.replace("  pull_request:\n", "", 1)
caller-write|C|s.replace("contents: read", "contents: write", 1)
caller-wrong-ref|C|s.replace("image-ci.yml@main", "docker-build-push.yml@main", 1)
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
  IMAGE_CI_ROOT=$scratch python3 -m unittest -q "$HERE/test_image_ci.py" >/dev/null 2>&1; s=$?
  if [ $s != 0 ]; then
    echo "killed    $name (structural)"
  else
    IMAGE_CI_ROOT=$scratch bash "$HERE/image-ci-local.sh" >/dev/null 2>&1; b=$?
    if [ $b != 0 ]; then echo "killed    $name (behaviour)"; else echo "SURVIVED  $name"; survived=1; fi
  fi
  rm -rf "$scratch"
done <<< "$MUTANTS"
BEHAVIOUR_ALWAYS="build-secret-id-unchecked"
BEHAVIOUR_BUILDX="build-secret-as-build-arg build-secret-echoed build-secret-leaked-label build-secret-leaked-context build-secret-not-passed"
if docker buildx version >/dev/null 2>&1; then BEHAVIOUR="$BEHAVIOUR_ALWAYS $BEHAVIOUR_BUILDX"
elif [ "${IMAGE_CI_REQUIRE_BUILDX:-0}" = 1 ]; then echo "SURVIVED  behaviour pass: docker buildx missing and IMAGE_CI_REQUIRE_BUILDX=1"; survived=1; BEHAVIOUR=$BEHAVIOUR_ALWAYS
else echo "skip      behaviour pass for $BEHAVIOUR_BUILDX: docker buildx not available here (CI runs it)"; BEHAVIOUR=$BEHAVIOUR_ALWAYS; fi
for want in $BEHAVIOUR; do
  line=$(printf '%s\n' "$MUTANTS" | grep "^$want|") || { echo "ERROR no mutant $want"; survived=1; continue; }
  IFS='|' read -r name which expr <<< "$line"
  scratch=$(mktemp -d)
  cp -R "$ROOT/.github" "$ROOT/workflow-templates" "$scratch/"
  python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); t=eval(sys.argv[2]); assert t!=s; open(p,"w").write(t)' "$scratch/$WFR" "$expr" \
    || { echo "ERROR mutant $name did not apply"; survived=1; rm -rf "$scratch"; continue; }
  if IMAGE_CI_ROOT=$scratch bash "$HERE/image-ci-local.sh" >/dev/null 2>&1; then echo "SURVIVED  $name (behaviour only)"; survived=1
  else echo "killed    $name (behaviour only)"; fi
  rm -rf "$scratch"
done
[ $survived = 0 ] && echo "ALL MUTANTS KILLED" || echo "MUTANTS SURVIVED"
exit $survived
