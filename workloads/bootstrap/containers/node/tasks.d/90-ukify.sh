#!/usr/bin/env bash

PACKAGES+=(python3-pefile)

ukify() {
  update-initramfs -u -k all
  local kernver vmlinuz initrd
  vmlinuz=$(readlink /vmlinuz)
  kernver=${vmlinuz#'boot/vmlinuz-'}
  initrd=$(readlink /initrd.img)
  rm /initrd.img /initrd.img.old /vmlinuz /vmlinuz.old
  mv "$vmlinuz" /boot/vmlinuz
  mv "$initrd" /boot/initrd.img
  /lib/systemd/ukify build \
    --uname="$kernver" \
    --linux=/boot/vmlinuz \
    --initrd=/boot/initrd.img \
    --cmdline="root=/run/initramfs/root.img bootserver=${CLUSTER_BOOTSERVER_FIXEDIPV4} noresume" \
    --output=/boot/vmlinuz.unsigned.efi
}