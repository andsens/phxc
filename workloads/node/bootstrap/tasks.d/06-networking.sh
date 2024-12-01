#!/usr/bin/env bash

PACKAGES+=(
  iproute2 # Used to determine MAC address
  curl # Image updates
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  systemd-timesyncd # various authentication protocols rely on synchronized time +/- skew
)

networking() {
  install_sd_unit 17-system/configure-hostname.service
  install_sd_unit 17-system/configure-networks.service
  systemctl enable systemd-networkd
  cp_tpl /etc/hosts.tmp
  cp_tpl --chmod=0755 /usr/local/bin/configure-networks
}
