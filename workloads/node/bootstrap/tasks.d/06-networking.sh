#!/usr/bin/env bash

PACKAGES+=(
  iproute2 # Used to determine MAC address
  curl # Image updates
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  systemd-timesyncd # various authentication protocols rely on synchronized time +/- skew
)

networking() {
  mkdir -p /etc/systemd/resolved.conf.d
  systemctl enable systemd-networkd
}
