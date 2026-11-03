#!/bin/bash
# PLAT-41: asserts the registry on localhost:5000 (the throwaway registry:2 service, nothing real) holds
# plat41-test:v2, built from the subfolder context 'sub', and that what it holds is the SUBFOLDER image
# (its /plat41 file carries the marker written into sub/Containerfile), not the root-context image.
# The local copies are removed first, so the content read below comes from the registry, not the daemon.
set -u
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
REG=localhost:5000
IMG=plat41-test

tags=$(curl -s "http://$REG/v2/$IMG/tags/list")
echo "$tags" | grep -q '"v2"' && ok "registry holds $IMG:v2" || bad "registry lacks $IMG:v2 (have: $tags)"

# The wrong-registry check: nothing for this image may sit under another repository path in the same registry.
cat=$(curl -s "http://$REG/v2/_catalog")
echo "$cat" | grep -q "\"$IMG\"" && ok "catalog lists $IMG at the top level" || bad "catalog lacks $IMG (have: $cat)"
echo "$cat" | grep -q "/$IMG" && bad "catalog lists $IMG under another path (have: $cat)" || ok "no copy of $IMG under another path"

docker rmi -f "$IMG:v2" "$REG/$IMG:v2" >/dev/null 2>&1 || true
if docker pull -q "$REG/$IMG:v2" >/dev/null 2>&1; then
  ok "pulled $REG/$IMG:v2 back from the registry"
  cid=$(docker create "$REG/$IMG:v2" /plat41)
  out=$(mktemp -d)
  docker cp "$cid:/plat41" "$out/plat41" 2>&1 || echo "docker cp failed"
  content=$(cat "$out/plat41" 2>/dev/null)
  docker rm "$cid" >/dev/null 2>&1 || true
  echo "$content" | grep -q 'PLAT41-SUBFOLDER-CONTEXT' \
    && ok "the pulled image holds the subfolder Containerfile (context 'sub' was used)" \
    || bad "the pulled image does not hold the subfolder Containerfile (got: $(echo "$content" | head -3 | tr '\n' ' '))"
else
  bad "could not pull $REG/$IMG:v2 back from the registry"
fi
[ $fail = 0 ] && echo "ALL PASSED" || echo "FAILED"
exit $fail
