#!/usr/bin/env bash

# klibc does not support loop device mounting
PACKAGES+=(
  systemd-sysv systemd-boot systemd-ukify # systemd bootup
  dracut dracut-network binutils zstd # initrd
  python3-pefile sbsigntool # UKI creation & signing
  dosfstools # Used for mounting ESP
  iproute2 curl # Used in settings to determine MAC address and then fetching settings
  systemd-resolved # DNS resolution setup
  avahi-daemon libnss-mdns # System reachability through mdns
  socat #  find-boot-server
  fdisk cryptsetup-bin # disk tooling
)

case $VARIANT in
  amd64) PACKAGES+=(linux-image-amd64) ;;
  arm64) PACKAGES+=(linux-image-arm64) ;;
  rpi*)
  wget -qO/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  PACKAGES+=(linux-image-rpi-2712 raspi-firmware raspi-config rpi-update rpi-eeprom)
  ;;
  default) fatal "Unknown variant: %s" "$VARIANT" ;;
esac

boot() {
  # Enable serial console
  systemctl enable serial-getty@ttyS0

  cp_tpl --raw /etc/dracut.conf.d/home-cluster.conf

  cp_tpl --raw -r /etc/systemd/system
  cp_tpl --raw -r --chmod=0755 /usr/local/bin
  cp_tpl --raw -r /usr/local/lib/home-cluster

  cp_tpl --raw --chmod=0755 \
    /usr/lib/dracut/modules.d/99home-cluster/parse-squashfs-root.sh \
    /usr/lib/dracut/modules.d/99home-cluster/module-setup.sh
  cp_tpl --raw -r /usr/lib/dracut/modules.d/99home-cluster/system

  cp_tpl --var BOOT_UUID /etc/systemd/system/boot.mount
  cp_tpl --raw /etc/systemd/system.conf.d/disk-uuids.conf
  cp_tpl --var VARIANT /etc/systemd/system.conf.d/variant.conf
  cp_tpl --var DISK_UUID --var BOOT_UUID --var DATA_UUID /etc/systemd/system.conf.d/disk-uuids.conf

  systemctl enable \
    report-final-node-state.service \
    report-initial-node-state.service \
    boot-partition.target \
    persistent-partition.target \
    persist-node-key.service \
    cache-node-config.service \
    configure-hostname.service \
    configure-networks.service

  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id

  # Networking setup
  systemctl enable systemd-networkd
  cp_tpl /etc/systemd/system/setup-cluster-dns.service
  systemctl enable setup-cluster-dns.service
  cp_tpl /etc/hosts.tmp

  if [[ $VARIANT = rpi5 ]]; then
    # Remove Raspberry Pi 4 boot code
    rm boot/firmware/bootcode.bin boot/firmware/fixup*.dat boot/firmware/start*.elf
  fi
}
