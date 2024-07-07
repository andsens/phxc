FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG ARCH
ENV ARCH=$ARCH

RUN /workspace/common-context/setup-debian.sh; \
  apt-get -y update; apt-get -y install --no-install-recommends \
  squashfs-tools guestfish dosfstools linux-image-${ARCH} shim-signed python3-venv \
  ; rm -rf /var/cache/apt/lists/*; \
  upkg add -gp step -b step_0.26.2/bin/step \
    https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.26.2/step_linux_0.26.2_${ARCH}.tar.gz \
    f5ab8947a11dab7b854d65111f71b582147945d62735576d80340d6dcb1adbf1; \
  python3 -m venv /signify; \
  /signify/bin/pip3 install \
    https://github.com/wbond/oscrypto/archive/d5f3437ed24257895ae1edd9e503cfb352e635a8.zip#sha256=6f54c4261ab6d56c9fe96b01c92abf99b06feb8836208c7e3fed894702d34b59 \
    signify==0.6.1 \
    docopt==0.6.2

ENTRYPOINT ["/scripts/create-boot-image.sh"]
