#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  systemd-timesyncd # boot-server communication
  fdisk cryptsetup-bin # disk tooling
)

case $VARIANT in
  amd64) ;;
  arm64) ;;
  rpi*) PACKAGES+=(raspi-config rpi-update rpi-eeprom) ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

system_setup() {
  local filepath systemd_units=(
    16-persist-keys/persist-machine-id.service
    16-persist-keys/keys-persisted.target
    17-system/configure-hostname.service
    17-system/configure-networks.service
    25-data-partition/disk-encryption-key.service
    25-data-partition/encrypt-data.service
    25-data-partition/mkfs-data.service
    25-data-partition/data-partition.target
    70-update-boot/update-boot.service
  )
  for filepath in "${systemd_units[@]}"; do
    cp_tpl --raw "_systemd_units/$filepath" -d "/etc/systemd/system/$(basename "$filepath")"
  done

  if [[ $VARIANT = rpi5 ]]; then
    cp_tpl --raw _systemd_units/05-keys/rpi5-otp-secret.service -d /etc/systemd/system/rpi5-otp-secret.service
  fi
  cp_tpl --var BOOT_UUID _systemd_units/15-boot-partition/boot.mount -d /etc/systemd/system/boot.mount
  # Do not time out mounting the boot or data partitions
  # download-node-config blocks indefinitely until it receives a configuration
  local devpath
  for devpath in "/dev/disk/by-partuuid/$BOOT_UUID" "/dev/disk/by-partuuid/$DATA_UUID" /dev/mapper/data; do
    local systemd_name
    systemd_name=$(systemd-escape -p "$devpath")
    mkdir -p "/etc/systemd/system/$systemd_name.device.d"
    printf '[Unit]\nJobRunningTimeoutSec=infinity\n' >"/etc/systemd/system/$systemd_name.device.d/50-device-timeout.conf"
  done

  cp_tpl --raw -r --chmod=0755 \
    /usr/local/bin/configure-networks \
    /usr/local/bin/update-boot

  systemctl enable update-boot.service

  ln -sf ../run/machine-id /etc/machine-id
  ln -sf ../../../run/machine-id /var/lib/dbus/machine-id

  cp_tpl /etc/crypttab /etc/fstab.tmp

  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id

  # Networking setup
  systemctl enable systemd-networkd
  cp_tpl /etc/hosts.tmp

  mkdir /var/lib/phoenix-cluster
}
