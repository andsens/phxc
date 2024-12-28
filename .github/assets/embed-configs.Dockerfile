FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

ARG TARGETARCH

RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends \
  guestfish dosfstools linux-image-${TARGETARCH}
rm -rf /var/cache/apt/lists/*
EOR

ENTRYPOINT ["/scripts/embed-configs.sh"]
