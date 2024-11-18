#!/usr/bin/env bash

initramfs() {
  local kernver
  kernver=$(echo /lib/modules/*)
  kernver=${kernver#'/lib/modules/'}
  dracut --kver "$kernver"
  # Remove kernel & initramfs symlinks and move real files to fixed location
  rm -f /vmlinuz* /initrd.img*
  mv "/boot/vmlinuz-${kernver}" /boot/vmlinuz
  mv "/boot/initramfs-${kernver}.img" /boot/initrd.img
}
