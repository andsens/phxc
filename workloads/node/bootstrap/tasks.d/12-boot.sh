#!/usr/bin/env bash

# klibc does not support loop device mounting
PACKAGES+=(
  systemd-sysv systemd-boot # systemd bootup
  initramfs-tools busybox util-linux zstd # initrd
  "linux-image-${ARCH?}"
  python3-pefile # UKI creation
  dosfstools # Used for mounting ESP
  iproute2 wget # Used in settings to determine MAC address and then fetching settings
  overlayroot # Used for making ro-root writeable
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  tpm2-tools openssl xxd curl systemd-timesyncd # Remote attestation for cluster authentication
)

boot() {
  # Hook for copying tooling into intramfs
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/home-cluster

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

  # Authentication towards the cluster
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/attest
  systemctl enable systemd-timesyncd

  # Root
  printf "squashfs\n" >>/etc/initramfs-tools/modules
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/local-premount/rootimg
  cp_tpl /etc/overlayroot.conf
  # root disk is a squashfs image, none of these are needed
  systemctl disable fstrim e2scrub_all e2scrub_reap
}
