FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

ENV DEBUG=false

RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends jq wget ca-certificates
wget -qO/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: https://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
Signed-By: /etc/apt/trusted.gpg.d/raspberrypi.asc
EOF
# Some deps are needed from bookworm
cat <<EOF >/etc/apt/sources.list.d/bookworm.sources
Types: deb
URIs: https://deb.debian.org/debian
Suites: bookworm bookworm-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://deb.debian.org/debian-security
Suites: bookworm-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
cat <<EOF >/etc/apt/preferences.d/priorities
Package: *
Pin: release a=trixie
Pin-Priority: 700

Package: *
Pin: release a=bookworm
Pin-Priority: 650
EOF
apt-get -y update
apt-get -y install --no-install-recommends rpi-eeprom rpiboot
rm -rf /var/cache/apt/lists/*
EOR

COPY --chmod=0755 setup-upkg.sh ./
RUN <<EOR
./setup-upkg.sh; rm /setup-upkg.sh
upkg add -gp docopt-lib-v2.0.2 https://github.com/andsens/docopt.sh/releases/download/v2.0.2/docopt-lib.sh.tar.gz d6997858e7f2470aa602fdd1e443d89b4e2084245b485e4b7924b0f388ec401e
upkg add -g https://github.com/orbit-online/records.sh/releases/download/v1.0.2/records.sh.tar.gz 201977ecc5fc9069d8eff12ba6adc9ce1286ba66c9aeee19184e26185cc6ef63
EOR

RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends \
  squashfs-tools cpio zstd dosfstools mtools fdisk curl systemd-ukify gettext \
  sbsigntool openssl xxd python3 python3-pycryptodome binutils
rm -rf /var/cache/apt/lists/*
EOR
