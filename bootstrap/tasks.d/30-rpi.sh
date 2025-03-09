#!/usr/bin/env bash

if [[ $VARIANT = rpi* ]]; then
  PACKAGES+=(rpi-eeprom flashrom)
  PACKAGES_TMP+=(libusb-1.0-0-dev libc6-dev gcc make pkgconf) # Deps for usbboot repo
  curl -Lso/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
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
fi

rpi() {
  if [[ $VARIANT = rpi* ]]; then
    local usbboottmp
    usbboottmp=$(mktemp -d)
    wget -qO>(tar -xzC "$usbboottmp" --strip-components=1) \
      "https://github.com/raspberrypi/usbboot/archive/refs/tags/20250129-123632.tar.gz"
    make -C "$usbboottmp" install
    rm -rf "$usbboottmp"
  else
    rm -rf /etc/systemd/system/rpi-eeprom-update.service.d \
           /etc/default/rpi-eeprom-update
  fi
}
