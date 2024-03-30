#!/usr/bin/env bash
# shellcheck disable=2064,2030,2031

mount_image() {
  local image_path=$1 dev_path
  local mount=mount losetup=losetup
  if [[ $UID != 0 ]]; then
    mount="sudo mount"
    losetup="sudo losetup"
  fi
  if [[ -z $2 ]]; then
    MOUNT_PATH=$(mktemp -d)
  else
    local MOUNT_PATH=$2
  fi
  dev_path=$($losetup --show --find --partscan "$image_path")
  if [[ -z $2 ]]; then
    trap "umount_image \"$MOUNT_PATH\" \"$dev_path\" true" EXIT SIGINT SIGTERM
  else
    trap "umount_image \"$MOUNT_PATH\" \"$dev_path\" false" EXIT SIGINT SIGTERM
  fi
  if [[ -b ${dev_path}p1 ]]; then
    $mount "${dev_path}p2" "$MOUNT_PATH"
    $mount "${dev_path}p1" "$MOUNT_PATH/boot/efi"
  else
    $mount "$dev_path" "$MOUNT_PATH"
  fi
}

umount_image() {
  local mount_path=$1 dev_path=$2 rm_mountpath=$3 timeout ret=0
  local umount=umount losetup=losetup
  if [[ $UID != 0 ]]; then
    umount="sudo umount"
    losetup="sudo losetup"
  fi
  if [[ -b ${dev_path}p1 ]]; then
    $umount -l "$mount_path/boot/efi" "$mount_path" || ret=$?
  else
    $umount -l "$mount_path" || ret=$?
  fi
  if [[ $ret != 0 ]] ; then
    warning "Failed to unmount %s" "$mount_path"
  else
    timeout=1000
    while mount | grep -q "$mount_path"; do
      sleep .1; timeout=$((timeout-100))
      [[ $timeout -gt 0 ]] || { warning "Timed out waiting for %s to unmount" "$mount_path"; break; }
    done
  fi
  if ! $losetup --detach "$dev_path"; then
    warning "Failed to detach loopdevice %s" "$dev_path"
    ret=1
  fi
  if $rm_mountpath; then
    if ! rmdir "$mount_path"; then
      warning "Unable to remove mount path %s" "$mount_path"
    fi
  fi
  return $ret
}
