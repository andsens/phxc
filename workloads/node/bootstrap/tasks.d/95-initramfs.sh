#!/usr/bin/env bash

initramfs() {
  local kernver
  kernver=$(echo /lib/modules/*)
  kernver=${kernver#'/lib/modules/'}
  dracut --force --kver "$kernver"
  # Move files to fixed location and remove symlinks
  mv "$(readlink /vmlinuz)" /boot/vmlinuz
  mv "$(readlink /initrd.img)" /boot/initrd.img
  rm -f /vmlinuz* /initrd.img*
}
