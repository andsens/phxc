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
)

case $VARIANT in
  amd64) PACKAGES+=(linux-image-amd64) ;;
  arm64) PACKAGES+=(linux-image-amd64) ;;
  rpi) PACKAGES+=(linux-image-rpi-v8 raspi-firmware) ;;
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

  # ESP mounting
  local modules=(vfat nls_cp437 nls_ascii)
  printf "%s\n" "${modules[@]}" >>/etc/initramfs-tools/modules
  cp_tpl --raw --chmod=0755 \
    /etc/initramfs-tools/scripts/init-top/mount-efi \
    /etc/initramfs-tools/scripts/init-bottom/umount-efi

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
}
