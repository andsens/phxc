#!/usr/bin/env bash

PACKAGES+=(overlayroot)

root() {
  printf "squashfs\n" >>/etc/initramfs-tools/modules
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/rootimg
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/local-premount/rootimg
  cp_tpl /etc/overlayroot.conf

  systemctl disable fstrim e2scrub_all e2scrub_reap
}
