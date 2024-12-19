FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG ARCH
ENV ARCH=$ARCH

RUN /workspace/common-context/setup-debian.sh; \
  set -x; \
  apt-get -y update; apt-get -y install --no-install-recommends \
  guestfish dosfstools linux-image-${ARCH} \
  ; rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/scripts/embed-configs.sh"]
