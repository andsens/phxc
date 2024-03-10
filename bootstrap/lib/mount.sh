#!/usr/bin/env bash
# shellcheck disable=2064,2030,2031

mount_image() {
  local image_path=$1 devpath
  if [[ -z $2 ]]; then
    MOUNT_PATH=$(mktemp -d)
  else
    local MOUNT_PATH=$2
  fi
  devpath=$(losetup --show --find --partscan "$image_path")
  if [[ -z $2 ]]; then
    trap "umount_image \"$MOUNT_PATH\" \"$devpath\" true" EXIT SIGINT SIGTERM
  else
    trap "umount_image \"$MOUNT_PATH\" \"$devpath\" false" EXIT SIGINT SIGTERM
  fi
  mount "${devpath}p2" "$MOUNT_PATH"
  mount "${devpath}p1" "$MOUNT_PATH/boot/efi"
}

umount_image() {
  local mount_path=$1 devpath=$2 rm_mountpath=${3:-false} timeout ret=0
  if ! umount -l "$mount_path/boot/efi" "$mount_path"; then
    warning "Failed to unmount %s" "$mount_path"
    ret=1
  else
    timeout=1000
    while mount | grep -q "$mount_path"; do
      sleep .1; timeout=$((timeout-100))
      [[ $timeout -gt 0 ]] || { warning "Timed out waiting for %s to unmount" "$mount_path"; break; }
    done
  fi
  if ! losetup --detach "$devpath"; then
    warning "Failed to detach loopdevice %s" "$devpath"
    ret=1
  fi
  if $rm_mountpath; then
    if ! rmdir "$mount_path"; then
      warning "Unable to remove mount path %s" "$mount_path"
    fi
  fi
  return $ret
}
