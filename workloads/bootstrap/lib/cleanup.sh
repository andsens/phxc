#!/usr/bin/env/bash

cleanup_image() {
  local root=${1:?}
  # During bootstrapping with kaniko these file can't be removed,
  # instead we do it when creating a PXE or UEFI image
  rm \
  "$root/etc/hostname" \
  "$root/etc/resolv.conf"
}
