#!/usr/bin/env bash

# busybox is needed by scripts in initramfs
PACKAGES+=(busybox systemd-sysv systemd-boot zstd util-linux initramfs-tools "linux-image-${ARCH?}")

boot() {
  :
}
