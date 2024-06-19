#!/usr/bin/env bash

PACKAGES+=(dosfstools)

esp_mount() {
  local modules=(vfat nls_cp437 nls_ascii)
  printf "%s\n" "${modules[@]}" >>/etc/initramfs-tools/modules
  cp_tpl --raw --chmod=0755 \
    /etc/initramfs-tools/scripts/init-top/mount-efi \
    /etc/initramfs-tools/scripts/init-bottom/umount-efi
}
