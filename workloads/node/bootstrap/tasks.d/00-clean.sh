#!/usr/bin/env bash

clean() {
  rm /etc/fstab
  # initramfs-tools get installed for some reason
  # even though we select dracut in the same install as we select the kernel image
  apt purge initramfs-tools
}
