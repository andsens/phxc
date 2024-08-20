#!/usr/bin/env bash

# klibc does not support loop device mounting
PACKAGES+=(
  systemd-sysv systemd-boot systemd-ukify # systemd bootup
  initramfs-tools busybox util-linux zstd # initrd
  python3-pefile sbsigntool # UKI creation & signing
  dosfstools # Used for mounting ESP
  iproute2 curl # Used in settings to determine MAC address and then fetching settings
  overlayroot # Used for making ro-root writeable
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  fdisk # disk tooling
  socat #  find-boot-server
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

  # Tooling for intramfs
  cp_tpl --raw --chmod=0755 \
    /etc/initramfs-tools/hooks/home-cluster \
    /etc/initramfs-tools/scripts/common.sh \
    /etc/initramfs-tools/scripts/node.sh \
    /etc/initramfs-tools/scripts/curl-boot-server.sh \
    /etc/initramfs-tools/scripts/disk-uuids.sh
  cp "$PKGROOT/.upkg/records.sh/records.sh" "/etc/initramfs-tools/scripts/records.sh"

  # Setup node-state.json & node-config.json
  cp_tpl --var VARIANT --chmod=0755 /etc/initramfs-tools/scripts/init-top/create-node-state
  cp_tpl --raw /etc/systemd/system/init-node-config.service
  systemctl enable init-node-config.service

  # Setup script for finding the boot-server
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-premount/find-boot-server

  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id

  # FAT32 boot partition mounting
  local modules=(vfat nls_cp437 nls_ascii)
  printf "%s\n" "${modules[@]}" >>/etc/initramfs-tools/modules

  # Root image
  printf "squashfs\n" >>/etc/initramfs-tools/modules
  cp_tpl --raw /etc/initramfs-tools/initramfs.conf
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/local-premount/rootimg
  cp_tpl /etc/overlayroot.conf

  # Networking setup
  systemctl enable systemd-networkd
  cp_tpl --raw /etc/systemd/system/setup-networking.service
  cp_tpl /etc/systemd/system/setup-cluster-dns.service
  systemctl enable setup-cluster-dns.service setup-networking.service
  cp_tpl /etc/hosts.tmp

  # Disk setup
  cp_tpl /etc/crypttab /etc/fstab.tmp
  cp_tpl --raw \
    /etc/systemd/system/setup-disk.service \
    /etc/systemd/system/persistent-mkfs.service
  systemctl enable \
    setup-disk.service \
    persistent-mkfs.service

  if [[ $VARIANT = rpi5 ]]; then
    # Remove Raspberry Pi 4 boot code
    rm boot/firmware/bootcode.bin boot/firmware/fixup*.dat boot/firmware/start*.elf
  fi
}
