#!/usr/bin/env bash

PACKAGES+=(
  systemd systemd-sysv # systemd bootup
  dosfstools # Used for mounting ESP
  systemd-resolved # DNS resolution setup
)

PACKAGES_TMP+=(
  dracut dracut-network binutils zstd # initramfs
)

case $VARIANT in
  amd64) PACKAGES_TMP+=(linux-image-amd64) ;;
  arm64) PACKAGES_TMP+=(linux-image-arm64) ;;
  rpi*)
  curl -Lso/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  PACKAGES_TMP+=(linux-image-rpi-2712)
  PACKAGES+=(raspi-firmware)
  ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

initramfs() {
  cp_tpl --var BOOT_UUID /etc/fstab.dracut
  cp_tpl /etc/systemd/system.conf.d/variant.conf --var VARIANT
  cp_tpl /etc/systemd/system.conf.d/disk-uuids.conf --var DISK_UUID --var BOOT_UUID --var DATA_UUID

  # Enable serial console
  systemctl enable serial-getty@ttyS0

  cp_tpl /etc/dracut.conf.d/phoenix-cluster.conf

  cp_tpl --chmod=0755 \
    /usr/lib/dracut/modules.d/99phoenix-cluster/parse-squashfs-root.sh \
    /usr/lib/dracut/modules.d/99phoenix-cluster/module-setup.sh
  cp_tpl -r /usr/lib/dracut/modules.d/99phoenix-cluster/system

  if [[ $VARIANT = rpi5 ]]; then
    # Remove Raspberry Pi 4 boot code
    rm boot/firmware/bootcode.bin boot/firmware/fixup*.dat boot/firmware/start*.elf
  fi

  local kernver
  kernver=$(echo /lib/modules/*)
  kernver=${kernver#'/lib/modules/'}
  dracut --force --kver "$kernver"
  # Move files to fixed location and remove symlinks
  mv "$(readlink /vmlinuz)" /boot/vmlinuz
  mv "$(readlink /initrd.img)" /boot/initrd.img
  rm -f /vmlinuz* /initrd.img*
  PACKAGES_PURGE+=("linux-image-$kernver")
}
