FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG ARCH
ENV ARCH=$ARCH

RUN /workspace/common-context/setup-debian.sh; \
  apt-get -y update; apt-get -y install --no-install-recommends \
  squashfs-tools guestfish ipxe-qemu dosfstools linux-image-${ARCH} python3-venv binutils curl \
  ; rm -rf /var/cache/apt/lists/*; \
  upkg add -g /workspace/common-context/smallstep.upkg.json; \
  python3 -m venv /signify; \
  /signify/bin/pip3 install \
    'https://github.com/wbond/oscrypto/archive/d5f3437ed24257895ae1edd9e503cfb352e635a8.zip#sha256=6f54c4261ab6d56c9fe96b01c92abf99b06feb8836208c7e3fed894702d34b59' \
    signify==0.6.1 \
    pyasn1==0.6.0 \
    docopt==0.6.2

# See https://github.com/wbond/oscrypto/issues/78
# for why we install oscrypto like this.

ENTRYPOINT ["/scripts/create-boot-image.sh"]
