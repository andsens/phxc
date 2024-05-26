#!/usr/bin/env bash

pxe() {
  printf "squashfs\n" >>/etc/initramfs-tools/modules
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/download-rootimg
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/local-premount/download-rootimg
}
