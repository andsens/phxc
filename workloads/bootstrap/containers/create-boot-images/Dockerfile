FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

RUN /workspace/common-context/setup-debian.sh

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  squashfs-tools guestfish dosfstools linux-image-amd64 shim-signed \
  ; rm -rf /var/cache/apt/lists/*; \
  upkg add -gp step -b step_0.26.2/bin/step \
    https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.26.2/step_linux_0.26.2_amd64.tar.gz \
    f5ab8947a11dab7b854d65111f71b582147945d62735576d80340d6dcb1adbf1

ENTRYPOINT ["/scripts/create-boot-images.sh"]
