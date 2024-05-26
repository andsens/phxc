#!/usr/bin/env bash

PACKAGES+=(
  systemd-resolved
  avahi-daemon libnss-mdns
)

network() {
  systemctl enable systemd-networkd

  cp_tpl /etc/systemd/system/setup-cluster-dns.service
  systemctl enable setup-cluster-dns.service
}
