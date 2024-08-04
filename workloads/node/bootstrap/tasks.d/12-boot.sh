#!/usr/bin/env bash

# klibc does not support loop device mounting
PACKAGES+=(
  systemd-sysv systemd-boot # systemd bootup
  initramfs-tools busybox util-linux zstd # initrd
  python3-pefile # UKI creation
  dosfstools # Used for mounting ESP
  iproute2 curl # Used in settings to determine MAC address and then fetching settings
  overlayroot # Used for making ro-root writeable
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  fdisk # setup-disk
)

case $VARIANT in
  amd64) PACKAGES+=(linux-image-amd64) ;;
  arm64) PACKAGES+=(linux-image-amd64) ;;
  rpi*)
  wget -qO/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  PACKAGES+=(linux-image-rpi-2712 raspi-firmware raspi-config rpi-update rpi-eeprom)
  ;;
  default) fatal "Unknown variant: %s" "$VARIANT" ;;
esac

boot() {
  # Enable serial console
  systemctl enable serial-getty@ttyS0

  # Hook for copying tooling into intramfs
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/home-cluster

  # Setup boot-state.json
  cp_tpl --chmod=0755 /etc/initramfs-tools/scripts/init-top/create-boot-state

  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id

  # FAT32 boot partition mounting
  local modules=(vfat nls_cp437 nls_ascii)
  printf "%s\n" "${modules[@]}" >>/etc/initramfs-tools/modules
  cp_tpl --raw --chmod=0755 \
    /etc/initramfs-tools/scripts/init-top/mount-boot \
    /etc/initramfs-tools/scripts/init-bottom/umount-boot

  # Settings
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/settings

  # Networking setup
  systemctl enable systemd-networkd
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/networking
  cp_tpl /etc/systemd/system/setup-cluster-dns.service
  systemctl enable setup-cluster-dns.service

  # Root
  printf "squashfs\n" >>/etc/initramfs-tools/modules
  cp_tpl --raw /etc/initramfs-tools/initramfs.conf
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/local-premount/rootimg
  cp_tpl /etc/overlayroot.conf
  # root disk is a squashfs image, none of these are needed
  systemctl disable fstrim e2scrub_all e2scrub_reap
  if [[ $VARIANT = rpi5 ]]; then
    # Remove Raspberry Pi 4 boot code
    rm boot/firmware/bootcode.bin boot/firmware/fixup*.dat boot/firmware/start*.elf
  fi

  # Disk creation
  cp_tpl --raw \
    /etc/systemd/system/setup-disk.service \
    /etc/systemd/system/update-boot.service
  systemctl enable setup-disk.service update-boot.service
}
