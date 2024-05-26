#!/usr/bin/env bash

PACKAGES+=(linux-image-amd64)

truenas_vm() {
  cp_tpl /etc/systemd/network/host.network

  mkdir /var/lib/persistent

  # https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html#x-systemd.makefs
  # The mkfs and growfs options are not available when specifying this mount as a systemd mount unit, so we use fstab
  printf "/dev/vdb  /var/lib/persistent   ext4    defaults,x-systemd.makefs,x-systemd.growfs\n" >>/etc/fstab

  cp_tpl /etc/systemd/system/link-k3s-data.service
  systemctl enable link-k3s-data.service
}
