#!/bin/bash
# Behaviour test for .github/workflows/image-ci.yml. Runs the workflow's own jobs and steps (tests/image-ci-run.py
# evaluates their `if:` and `${{ }}` as Actions does) on the fixture repos in tests/fixtures/, against a throwaway
# registry container on 127.0.0.1 (registry:2, pinned by digest). Nothing reaches aloma.azurecr.io or anywhere real:
# the registry input is the local one and the credentials are dummies.
#   A  pull_request, push asked for     tests run; image built once; nothing pushed; no digest
#   B  push to main, push asked for     image sha-<commit> in the registry; digest output = the registry's digest;
#                                       ref = image:tag@digest; revision label = the commit; prepare ran before build
#   C  same commit again, changed file  the existing tag is not overwritten; the digest output is still B's
#   D  failing test, push to main       build job skipped; nothing in the registry
#   E  push to main, push not asked     built, nothing pushed
#   F  push to another branch           built, nothing pushed
#   G  build secret passed (dummy)      the build stage read it (BuildKit secret mount, its length recorded); the value
#                                       is nowhere in the final image (filesystem export, config, labels, env, history)
#                                       nor in the run log
#   H  same fixture, no build secret    the build fails: proves G's build really needed the secret
#   I  build secret with a bad id       refused before any build (a comma would add options such as src= to --secret)
# G and H need BuildKit (docker buildx); without it they are skipped, unless IMAGE_CI_REQUIRE_BUILDX=1 (CI sets it),
# when a missing buildx fails the test. The build secret is a random dummy, never a real one.
# Needs docker, python3 with PyYAML, curl. IMAGE_CI_ROOT points it at another checkout (tests/image-ci-mutants.sh).
# Cleans up its registry container, its images and its login whatever happens.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${IMAGE_CI_ROOT:-$(dirname "$HERE")}
WF="$ROOT/.github/workflows/image-ci.yml"
RUN="python3 $HERE/image-ci-run.py"
REGISTRY_IMAGE="registry@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373"   # registry:2
NAME=imageci-fixture-$$-$RANDOM
REG_CONTAINER=$NAME-registry
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
WORK=$(mktemp -d)

cleanup() {
  docker rm -f "$REG_CONTAINER" >/dev/null 2>&1
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -F "/$NAME:" | while read -r i; do docker rmi -f "$i" >/dev/null 2>&1; done
  [ -n "${PORT:-}" ] && docker logout "127.0.0.1:$PORT" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

docker run -d --name "$REG_CONTAINER" --label aloma.session=devops -p 127.0.0.1::5000 "$REGISTRY_IMAGE" >/dev/null \
  || { echo "FAIL  could not start the local registry"; exit 1; }
PORT=$(docker port "$REG_CONTAINER" 5000/tcp | head -1 | sed 's/.*://')
REG="127.0.0.1:$PORT"
for _ in $(seq 1 30); do curl -sf "http://$REG/v2/" >/dev/null && break; sleep 1; done
curl -sf "http://$REG/v2/" >/dev/null || { echo "FAIL  the local registry at $REG never answered"; exit 1; }
IMAGE="$REG/$NAME"

ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'
registry_digest() {  # $1 tag -> the digest the registry holds for it, or nothing
  curl -s -I -H "Accept: $ACCEPT" "http://$REG/v2/$NAME/manifests/$1" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p'
}

newsha() { python3 -c "import secrets; print(secrets.token_hex(20))"; }

run() {  # $1 fixture  $2 case dir  $3 sha  $4 event  $5 ref  $6 push(true|false)  [$7 build secret  [$8 build-secret-id]]
  mkdir -p "$2"; cp -R "$HERE/fixtures/$1/." "$2/"
  local ctx
  ctx=$(python3 -c '
import json, sys
fixture, image, reg, sha, event, ref, push, bsec, bsid = sys.argv[1:]
inputs = {"image-name": image, "registry": reg, "test-command": "./test.sh",
          "prepare-command": "echo prepared > prepared.txt", "push": push == "true"}
secrets = {"REGISTRY_USERNAME": "dummy", "REGISTRY_PASSWORD": "dummy"}
if bsec:
    secrets["BUILD_SECRET"] = bsec
if bsid:
    inputs["build-secret-id"] = bsid
print(json.dumps({"inputs": inputs, "secrets": secrets,
  "github": {"sha": sha, "ref": ref, "event_name": event, "repository": "aloma-io/fixture"}}))' \
    "$1" "$NAME" "$REG" "$3" "$4" "$5" "$6" "${7:-}" "${8:-}")
  $RUN "$WF" "$2" "$ctx" > "$2/.result.json" 2>"$2/.runner.err" || { cat "$2/.runner.err"; return 1; }
}

jq_() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"d": d}))' "$@"; }

# A: pull request
SHA_A=$(newsha); A="$WORK/A"
run image-green "$A" "$SHA_A" pull_request refs/pull/1/merge true || bad "A: runner error"
[ "$(jq_ "$A/.result.json" 'd["jobs"]["test"]["result"]')" = success ] && ok "A: test job passes" || bad "A: test job $(jq_ "$A/.result.json" 'd["jobs"]["test"]["result"]')"
[ -f "$A/test-ran.marker" ] && ok "A: the repo's test command ran" || bad "A: the test command never ran"
[ "$(jq_ "$A/.result.json" 'd["jobs"]["build"]["result"]')" = success ] && ok "A: build job passes" || bad "A: build job failed: $(tail -5 "$A/.image-ci-run.log")"
docker image inspect "$IMAGE:sha-$SHA_A" >/dev/null 2>&1 && ok "A: image $NAME:sha-<commit> built" || bad "A: no local image $NAME:sha-$SHA_A"
[ -z "$(registry_digest "sha-$SHA_A")" ] && ok "A: nothing pushed from a pull request" || bad "A: a pull request pushed an image"
[ -z "$(jq_ "$A/.result.json" 'd["jobs"]["build"]["outputs"].get("digest","")')" ] && ok "A: no digest output" || bad "A: digest output on a PR"

# B: push to main
SHA_B=$(newsha); B="$WORK/B"
run image-green "$B" "$SHA_B" push refs/heads/main true || bad "B: runner error"
[ "$(jq_ "$B/.result.json" 'd["jobs"]["build"]["result"]')" = success ] && ok "B: build job passes" || bad "B: build job failed: $(tail -8 "$B/.image-ci-run.log")"
REG_B=$(registry_digest "sha-$SHA_B")
OUT_B=$(jq_ "$B/.result.json" 'd["jobs"]["build"]["outputs"].get("digest","")')
REF_B=$(jq_ "$B/.result.json" 'd["jobs"]["build"]["outputs"].get("ref","")')
TAG_B=$(jq_ "$B/.result.json" 'd["jobs"]["build"]["outputs"].get("tag","")')
[ -n "$REG_B" ] && ok "B: registry holds $NAME:sha-<commit>" || bad "B: registry lacks sha-$SHA_B"
[[ "$OUT_B" =~ ^sha256:[0-9a-f]{64}$ ]] && ok "B: digest output is sha256:<64 hex>" || bad "B: digest output '$OUT_B'"
[ -n "$REG_B" ] && [ "$OUT_B" = "$REG_B" ] && ok "B: digest output = the registry's digest" || bad "B: digest output '$OUT_B', registry '$REG_B'"
[ "$TAG_B" = "sha-$SHA_B" ] && ok "B: tag output sha-<full commit>" || bad "B: tag output '$TAG_B'"
[ "$REF_B" = "$IMAGE:sha-$SHA_B@$REG_B" ] && ok "B: ref output image:tag@digest" || bad "B: ref output '$REF_B'"
REV=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$IMAGE:sha-$SHA_B" 2>/dev/null)
[ "$REV" = "$SHA_B" ] && ok "B: revision label = the commit" || bad "B: revision label '$REV'"
TAGS=$(curl -s "http://$REG/v2/$NAME/tags/list")
python3 -c 'import json,sys; t=json.loads(sys.argv[1]).get("tags") or []; sys.exit(0 if all(x.startswith("sha-") for x in t) else 1)' "$TAGS" \
  && ok "B: only sha- tags in the registry ($TAGS)" || bad "B: other tags pushed: $TAGS"

# C: same commit, different content: the tag must not move
C="$WORK/C"; mkdir -p "$C"; cp -R "$HERE/fixtures/image-green/." "$C/"; echo "app v2 (must never reach the registry)" > "$C/app.txt"
docker rmi -f "$IMAGE:sha-$SHA_B" >/dev/null 2>&1
ctx=$(python3 -c '
import json, sys
print(json.dumps({"inputs": {"image-name": sys.argv[1], "registry": sys.argv[2], "test-command": "./test.sh",
  "prepare-command": "echo prepared > prepared.txt", "push": True},
  "secrets": {"REGISTRY_USERNAME": "dummy", "REGISTRY_PASSWORD": "dummy"},
  "github": {"sha": sys.argv[3], "ref": "refs/heads/main", "event_name": "push", "repository": "aloma-io/fixture"}}))' "$NAME" "$REG" "$SHA_B")
$RUN "$WF" "$C" "$ctx" > "$C/.result.json" 2>"$C/.runner.err" || bad "C: runner error $(cat "$C/.runner.err")"
[ "$(jq_ "$C/.result.json" '[x["result"] for x in d["jobs"]["build"]["steps"] if x["id"]=="push"][0]')" = skipped ] \
  && ok "C: push step skipped for an existing tag" || bad "C: the push step ran for a tag that already exists"
[ "$(registry_digest "sha-$SHA_B")" = "$REG_B" ] && ok "C: existing tag not overwritten" || bad "C: the tag moved to $(registry_digest "sha-$SHA_B")"
[ "$(jq_ "$C/.result.json" 'd["jobs"]["build"]["outputs"].get("digest","")')" = "$REG_B" ] && ok "C: digest output is the existing one" \
  || bad "C: digest output '$(jq_ "$C/.result.json" 'd["jobs"]["build"]["outputs"].get("digest","")')', want $REG_B"

# D: failing test
SHA_D=$(newsha); D="$WORK/D"
run image-red-test "$D" "$SHA_D" push refs/heads/main true || bad "D: runner error"
[ "$(jq_ "$D/.result.json" 'd["jobs"]["test"]["result"]')" = failure ] && ok "D: test job fails" || bad "D: test job did not fail"
[ "$(jq_ "$D/.result.json" 'd["jobs"]["build"]["result"]')" = skipped ] && ok "D: build skipped after a failing test" || bad "D: build ran after a failing test"
docker image inspect "$IMAGE:sha-$SHA_D" >/dev/null 2>&1 && bad "D: an image was built" || ok "D: no image built"
[ -z "$(registry_digest "sha-$SHA_D")" ] && ok "D: nothing pushed" || bad "D: pushed after a failing test"

# E: main push without push asked; F: push to another branch
for c in "E push refs/heads/main false" "F push refs/heads/feature true"; do
  set -- $c; S=$(newsha); W="$WORK/$1"
  run image-green "$W" "$S" "$2" "$3" "$4" || bad "$1: runner error"
  [ "$(jq_ "$W/.result.json" 'd["jobs"]["build"]["result"]')" = success ] && ok "$1: build job passes" || bad "$1: build failed"
  [ -z "$(registry_digest "sha-$S")" ] && ok "$1: nothing pushed ($2 $3 push=$4)" || bad "$1: pushed ($2 $3 push=$4)"
done

# G, H: the build secret (BuildKit secret mount); I: a bad secret id
DUMMY="not-a-real-secret-$(python3 -c 'import secrets; print(secrets.token_hex(12))')"
build_result() { jq_ "$1/.result.json" 'd["jobs"]["build"]["result"]'; }
if docker buildx version >/dev/null 2>&1; then
  SHA_G=$(newsha); G="$WORK/G"
  run image-build-secret "$G" "$SHA_G" pull_request refs/pull/1/merge false "$DUMMY" || bad "G: runner error"
  [ "$(build_result "$G")" = success ] && ok "G: build with a build secret passes" || bad "G: build failed: $(tail -8 "$G/.image-ci-run.log")"
  LEN=$(docker run --rm "$IMAGE:sha-$SHA_G" cat /secret-length 2>/dev/null)
  [ "$LEN" = "${#DUMMY}" ] && ok "G: the build stage read the secret (length $LEN)" || bad "G: secret length in the build '$LEN', want ${#DUMMY}"
  cid=$(docker create "$IMAGE:sha-$SHA_G" true 2>/dev/null)
  if [ -n "$cid" ]; then
    docker export "$cid" | LC_ALL=C grep -aqF "$DUMMY" && bad "G: the secret value is in the final image's files" || ok "G: secret value not in the final image's files"
    docker rm "$cid" >/dev/null 2>&1
  else bad "G: could not create a container from the image"; fi
  docker image inspect "$IMAGE:sha-$SHA_G" | grep -qF "$DUMMY" && bad "G: the secret value is in the image config (env/labels)" || ok "G: secret value not in the image config"
  docker history --no-trunc "$IMAGE:sha-$SHA_G" | grep -qF "$DUMMY" && bad "G: the secret value is in the image history" || ok "G: secret value not in the image history"
  grep -qF "$DUMMY" "$G/.image-ci-run.log" && bad "G: the secret value was printed to the log" || ok "G: secret value not in the log"
  SHA_H=$(newsha); H="$WORK/H"
  run image-build-secret "$H" "$SHA_H" pull_request refs/pull/1/merge false || bad "H: runner error"
  [ "$(build_result "$H")" = failure ] && ok "H: without the secret the fixture's build fails (G really used it)" || bad "H: build $(build_result "$H") without the secret"
elif [ "${IMAGE_CI_REQUIRE_BUILDX:-0}" = 1 ]; then
  bad "G/H: docker buildx is not available and IMAGE_CI_REQUIRE_BUILDX=1"
else
  echo "skip  G/H: docker buildx not available here (BuildKit secret mounts need it); CI runs them"
fi
SHA_I=$(newsha); I="$WORK/I"
run image-green "$I" "$SHA_I" pull_request refs/pull/1/merge false "$DUMMY" "aloma_token,src=/etc/hostname" || bad "I: runner error"
[ "$(build_result "$I")" = failure ] && grep -q "bad build-secret-id" "$I/.image-ci-run.log" \
  && ok "I: a bad build-secret-id is refused" || bad "I: bad build-secret-id not refused (build $(build_result "$I"))"
docker image inspect "$IMAGE:sha-$SHA_I" >/dev/null 2>&1 && bad "I: an image was built" || ok "I: no image built"
grep -qF "$DUMMY" "$I/.image-ci-run.log" && bad "I: the secret value was printed to the log" || ok "I: secret value not in the log"

[ $fail = 0 ] && echo "ALL PASSED" || echo "FAILED"
exit $fail
