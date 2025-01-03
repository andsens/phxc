#!/usr/bin/env bash

PACKAGES+=(
  systemd systemd-sysv # systemd bootup
  dosfstools # Used for mounting ESP
  systemd-resolved # DNS resolution setup
  dracut # Leave installed to avoid reinstalling initramfs-tools
)

PACKAGES_TMP+=(
  dracut-network binutils zstd # initramfs
)

case $VARIANT in
  amd64) PACKAGES+=(linux-image-amd64) ;;
  arm64) PACKAGES+=(linux-image-arm64) ;;
  rpi*)
  curl -Lso/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  PACKAGES+=(linux-image-rpi-2712 raspi-firmware)
  ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

# Disable initramfs updates until we are ready
export INITRD=No

initramfs() {
  # Re-enable initramfs updates
  unset INITRD

  # Enable serial console
  systemctl enable serial-getty@ttyS0

  chmod 0755 /usr/lib/dracut/modules.d/99phxc/parse-squashfs-root.sh \
             /usr/lib/dracut/modules.d/99phxc/module-setup.sh

  mkdir -p /mnt/overlay/image /mnt/overlay/upper

  if [[ $VARIANT = rpi5 ]]; then
    # Remove Raspberry Pi 4 boot code
    rm boot/firmware/bootcode.bin boot/firmware/fixup*.dat boot/firmware/start*.elf
  fi

  local kernver
  kernver=$(echo /lib/modules/*)
  kernver=${kernver#'/lib/modules/'}
  dracut --force --kver "$kernver"
  # Move files to fixed location and remove symlinks
  mv "/boot/vmlinuz-$kernver" /boot/vmlinuz
  mv "/boot/initrd.img-$kernver" /boot/initrd.img
}
