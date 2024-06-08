FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

RUN /workspace/common-context/setup-debian.sh

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  squashfs-tools guestfish dosfstools linux-image-amd64 \
  ; rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/scripts/create-boot-images.sh"]
