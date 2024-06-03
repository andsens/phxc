#!/usr/bin/env bash

PACKAGES+=(wget iproute2)

settings() {
  rm /var/lib/dbus/machine-id /etc/machine-id
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/settings
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/settings
}
