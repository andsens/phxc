#!/usr/bin/env bash

PACKAGES+=(
  iproute2 # Used to determine NICs (for avahi) and IPs (for dropbear msg in initramfs)
  curl # Image updates
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  systemd-timesyncd # various authentication protocols rely on synchronized time +/- skew
)

networking() {
  systemctl enable systemd-networkd
}
