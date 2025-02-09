FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

ARG TARGETARCH
ENV DEBUG=false

RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends jq wget ca-certificates
rm -rf /var/cache/apt/lists/*
EOR

COPY --chmod=0755 setup-upkg.sh ./
RUN <<EOR
./setup-upkg.sh
upkg add -gp docopt-lib-v2.0.2 https://github.com/andsens/docopt.sh/releases/download/v2.0.2/docopt-lib.sh.tar.gz d6997858e7f2470aa602fdd1e443d89b4e2084245b485e4b7924b0f388ec401e
upkg add -g https://github.com/orbit-online/records.sh/releases/download/v1.0.2/records.sh.tar.gz 201977ecc5fc9069d8eff12ba6adc9ce1286ba66c9aeee19184e26185cc6ef63
EOR

RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends \
  linux-image-${TARGETARCH} guestfish dosfstools curl systemd-ukify sbsigntool gettext
EOR

ENTRYPOINT ["/scripts/create-boot-image.sh"]
