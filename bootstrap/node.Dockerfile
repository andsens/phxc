ARG DISK_UTILS_IMG=ghcr.io/andsens/phxc-disk-utils:latest

FROM debian:trixie AS node-base
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG VARIANT
ARG DEBUG=false
ARG LOGLEVEL=info

COPY --chmod=0755 setup-upkg.sh /setup-upkg.sh
RUN --mount=from=bundle,target=/bundle <<EOR
apt-get -qq update
apt-get -y install --no-install-recommends jq wget ca-certificates gettext

/setup-upkg.sh; rm /setup-upkg.sh
upkg add -gp docopt-lib-v2.0.2 https://github.com/andsens/docopt.sh/releases/download/v2.0.2/docopt-lib.sh.tar.gz d6997858e7f2470aa602fdd1e443d89b4e2084245b485e4b7924b0f388ec401e
upkg add -g https://github.com/orbit-online/records.sh/releases/download/v1.0.2/records.sh.tar.gz 201977ecc5fc9069d8eff12ba6adc9ce1286ba66c9aeee19184e26185cc6ef63

upkg add -g /bundle/bundle.tar.gz
/usr/local/lib/upkg/.upkg/phxc/bootstrap/scripts/run-tasks.sh

mv /var /usr/local/lib/phxc/var-template
mkdir /var
rm -rf /var/lib/apt/lists/*
EOR

COPY --from=root.post . /

FROM $DISK_UTILS_IMG
ARG VARIANT
ARG CHOWN
ARG DEBUG=false
ARG LOGLEVEL=info

RUN --mount=from=node-base,target=/workspace/root \
    --mount=from=secureboot,target=/workspace/secureboot \
    --mount=from=admin,target=/workspace/admin \
    <<EOR
/workspace/root/usr/local/lib/upkg/.upkg/phxc/bootstrap/scripts/create-image.sh
EOR
