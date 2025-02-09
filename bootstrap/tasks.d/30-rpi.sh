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
  # Some deps are needed from bookworm
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
  if [[ $VARIANT != rpi* ]]; then
    rm /usr/local/bin/phxc-rpi
    return 0
  fi

  local kver kerneltmp rpi_suffix
  kerneltmp=$(mktemp -d)
  wget -qO>(tar -xzC "$kerneltmp" --strip-components=1) \
    "https://github.com/raspberrypi/firmware/archive/5eaa42401e9625415934c97baae5a8d65933768c.tar.gz"
  case "$VARIANT" in
    rpi2|rpi3) rpi_suffix=7 ;;
    rpi4) rpi_suffix=8 ;;
    rpi5) rpi_suffix=_2712 ;;
  esac
  uname_path="$kerneltmp/extra/uname_string${rpi_suffix}"
  kver=$(grep -o '^Linux version [^ ]\+' "$uname_path" | cut -d' ' -f3)
  mkdir /usr/lib/modules
  cp -r "$kerneltmp/modules/$kver" "/usr/lib/modules/$kver"
  cp "$kerneltmp/boot/kernel${rpi_suffix}.img" "/boot/vmlinuz-$kver"
  ln -s "boot/vmlinuz-$kver" /vmlinuz
  ln -s "boot/vmlinuz-$kver" /vmlinuz.old

  mkdir /boot/firmware
  cp -r "$kerneltmp/boot/overlays" /boot/firmware/overlays
  case "$VARIANT" in
    rpi2)
      cp "$kerneltmp/boot/start_x.elf" \
          "$kerneltmp/boot"/bcm*-rpi-2* \
          /boot/firmware
      ;;
    rpi3)
      cp "$kerneltmp/boot/start_x.elf" \
          "$kerneltmp/boot"/bcm2710-rpi-3* \
          /boot/firmware
      ;;
    rpi4)
      cp "$kerneltmp/boot/start4x.elf" \
          "$kerneltmp/boot"/bcm2711* \
          /boot/firmware
      ;;
    rpi5)
      cp "$kerneltmp/boot"/bcm2712* /boot/firmware
      ;;
  esac
  rm -rf "$kerneltmp"
}
