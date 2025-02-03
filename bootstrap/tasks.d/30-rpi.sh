#!/usr/bin/env bash

if [[ $VARIANT = rpi* ]]; then
  PACKAGES+=(raspi-config rpi-update rpi-eeprom)
  curl -Lso/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  cat <<EOF >/etc/apt/sources.list.d/bookworm.sources
Types: deb
URIs: http://deb.debian.org/debian
Suites: bookworm bookworm-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
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
fi

rpi() {
  [[ $VARIANT = rpi* ]] || rm /usr/local/bin/phxc-rpi
}
