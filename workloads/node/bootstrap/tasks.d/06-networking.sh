#!/usr/bin/env bash

PACKAGES+=(
  iproute2 # Used to determine MAC address
  curl # Image updates
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  systemd-timesyncd # various authentication protocols rely on synchronized time +/- skew
)

networking() {
  install_sd_unit networking/configure-hostname.service
  install_sd_unit networking/configure-networks.service
  install_sd_unit networking/configure-resolved.service --var DEFAULT_CLUSTER_DOMAIN
  mkdir -p /etc/systemd/resolved.conf.d
  systemctl enable systemd-networkd
  cp_tpl /etc/systemd/network/zzz-dhcp.network
  cp_tpl /etc/hosts.tmp
}
