#!/usr/bin/env bash

PACKAGES+=(wget iproute2)

firstboot() {
  rm /var/lib/dbus/machine-id /etc/machine-id
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/download-settings
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/download-settings
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/setup-networking
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/setup-networking
}
