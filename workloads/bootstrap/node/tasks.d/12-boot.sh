#!/usr/bin/env bash

# klibc does not support loop device mounting
PACKAGES+=(busybox systemd-sysv systemd-boot zstd util-linux initramfs-tools "linux-image-${ARCH?}")

boot() {
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/home-cluster
}
