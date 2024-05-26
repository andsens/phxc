#!/usr/bin/env bash

PACKAGES+=(
  systemd-resolved
  avahi-daemon libnss-mdns
)

network() {
  systemctl enable systemd-networkd

  : "${MACHINE_NIC_LAN0_NAME:?}"
  cp_tpl /etc/systemd/network/lan0.network

  cp_tpl /etc/systemd/system/setup-cluster-dns.service
  systemctl enable setup-cluster-dns.service
}
