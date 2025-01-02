FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

ARG TARGETARCH

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

# See https://github.com/wbond/oscrypto/issues/78 for why we install oscrypto like this.
RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends \
  squashfs-tools guestfish ipxe-qemu dosfstools linux-image-${TARGETARCH} python3-venv binutils curl \
  systemd-ukify systemd-boot-efi shim-signed python3-pefile sbsigntool gettext
python3 -m venv /signify
/signify/bin/pip3 install \
  signify==0.6.1 pyasn1==0.6.0 docopt==0.6.2 \
  'https://github.com/wbond/oscrypto/archive/d5f3437ed24257895ae1edd9e503cfb352e635a8.zip#sha256=6f54c4261ab6d56c9fe96b01c92abf99b06feb8836208c7e3fed894702d34b59'
rm -rf /var/cache/apt/lists/*
EOR

ENTRYPOINT ["/scripts/create-boot-image.sh"]
