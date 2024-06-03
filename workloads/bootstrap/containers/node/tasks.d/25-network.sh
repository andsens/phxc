#!/usr/bin/env bash

PACKAGES+=(
  systemd-resolved
  avahi-daemon libnss-mdns
)

network() {
  systemctl enable systemd-networkd
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/hooks/networking
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/networking

  cp_tpl --raw --chmod=0755 /usr/local/bin/setup-cluster-dns
  cp_tpl /etc/systemd/system/setup-cluster-dns.service
  systemctl enable setup-cluster-dns.service
}
