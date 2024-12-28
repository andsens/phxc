ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache bash
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN <<EOR
apk add jq py3-virtualenv gettext-envsubst curl
virtualenv /usr/local/lib/yq
/usr/local/lib/yq/bin/pip3 install yq
ln -s /usr/local/lib/yq/bin/yq /usr/local/bin/yq
EOR

COPY --chmod=0755 setup-upkg.sh ./
COPY kubectl.upkg.json step-cli.upkg.json ./
RUN <<EOR
./setup-upkg.sh
upkg add -gp docopt-lib-v2.0.2 https://github.com/andsens/docopt.sh/releases/download/v2.0.2/docopt-lib.sh.tar.gz d6997858e7f2470aa602fdd1e443d89b4e2084245b485e4b7924b0f388ec401e
upkg add -g https://github.com/orbit-online/records.sh/releases/download/v1.0.2/records.sh.tar.gz 201977ecc5fc9069d8eff12ba6adc9ce1286ba66c9aeee19184e26185cc6ef63
upkg add -g kubectl.upkg.json
upkg add -g step-cli.upkg.json
rm setup-upkg.sh kubectl.upkg.json step-cli.upkg.json
EOR
