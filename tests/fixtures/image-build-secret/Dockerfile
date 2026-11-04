# Fixture image for tests/image-ci-local.sh cases G-H: the build stage needs a BuildKit secret (it fails without one)
# and records only its length; the final image must hold none of it (no file, no env, no label, no history line).
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc AS build
# a fresh nonce per case (written by the test): BuildKit's cache key ignores the secret's value, so without it case H
# would reuse G's cached layer and pass without a secret
COPY nonce.txt /nonce.txt
RUN --mount=type=secret,id=aloma_token test -s /run/secrets/aloma_token && wc -c < /run/secrets/aloma_token | tr -d ' ' > /secret-length

FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
LABEL aloma.session=devops
COPY --from=build /secret-length /secret-length
# the whole build context, so a secret written into it by the workflow would show up in the image
COPY . /context/
RUN test ! -e /run/secrets/aloma_token && [ -z "$(ls -A /run/secrets 2>/dev/null)" ]
