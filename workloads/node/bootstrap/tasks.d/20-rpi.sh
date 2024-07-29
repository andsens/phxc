#!/usr/bin/env bash

if [[ ${VARIANT:?} = 'rpi' ]]; then
  wget -qO/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  PACKAGES+=(raspi-config rpi-update rpi-eeprom)
fi

rpi() {
  if [[ ${VARIANT:?} = rpi ]]; then
    # See corresponding file in assets for explanation
    cp_tpl --raw --chmod=0755 /usr/bin/ischroot

    info "Downloading & extracting Raspberry PI firmware"
    mkdir -p /boot/firmware
    wget -qO- https://github.com/raspberrypi/firmware/archive/refs/tags/1.20240529.tar.gz | \
      tar -xzC /boot/firmware --strip-components=2 firmware-1.20240529/boot
    rm -f /boot/firmware/kernel*
  fi
}
