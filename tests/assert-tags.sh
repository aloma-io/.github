#!/bin/bash
# Asserts what the build and push actions produced. Inputs (env): PRIMARY, ALL (newline-separated), and the
# registry on localhost:5000. Expected tags: the two given ('v1','stable'), the first 8 characters of the commit SHA,
# and the branch name with "/" replaced by "-".
set -u
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
SHA8=$(git rev-parse HEAD | cut -c1-8)
BRANCH=$(echo "${GITHUB_REF_NAME:-local}" | tr '/' '-')

[ "$PRIMARY" = "v1" ] && ok "primary tag is the first given tag (v1)" || bad "primary tag '$PRIMARY', want v1"
for t in v1 stable "$SHA8" "$BRANCH"; do
  echo "$ALL" | grep -qx -- "$t" && ok "build output carries tag $t" || bad "build output lacks tag $t (have: $(echo "$ALL" | tr '\n' ' '))"
done
tags=$(curl -s http://localhost:5000/v2/plat30-test/tags/list)
for t in v1 stable "$SHA8" "$BRANCH"; do
  echo "$tags" | grep -q "\"$t\"" && ok "registry holds plat30-test:$t" || bad "registry lacks plat30-test:$t (have: $tags)"
done
echo "$tags" | grep -q '"[^"]*/[^"]*"' && bad "registry holds a tag containing '/'" || ok "no tag contains '/'"
[ $fail = 0 ] && echo "ALL PASSED" || echo "FAILED"
exit $fail
