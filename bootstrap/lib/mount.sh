#!/usr/bin/env bash

# shellcheck disable=2064
image_mounted() (
  local image_path=$1 mount_path=$2
  trap "umount \"$mount_path/boot/efi\"; umount \"$mount_path\"; losetup --detach \"$devpath\"" EXIT SIGINT SIGTERM
  devpath=$(losetup --show --find --partscan "$image_path")
  mount "${devpath}p2" "$mount_path"
  mount "${devpath}p1" "$mount_path/boot/efi"
  while true; do sleep 3600; done
)
