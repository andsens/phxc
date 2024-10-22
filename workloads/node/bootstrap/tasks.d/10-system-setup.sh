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
  default) fatal "Unknown variant: %s" "$VARIANT" ;;
esac

system_setup() {
  local filepath systemd_units=(
    05-keys/random-secret.service
    05-keys/surrogate-key.service
    05-keys/authn-key.service
    05-keys/credential-key.service
    10-registry/node-config.service
    10-registry/initial-node-state.service
    14-partition-disk/partition-disk.service
    15-boot-partition/boot-partition.target
    15-boot-partition/boot-cache-dir.service
    15-boot-partition/mkfs-boot.service
    16-persist-keys/cache-node-config.service
    16-persist-keys/persist-authn-key.service
    16-persist-keys/persist-credential-key.service
    16-persist-keys/persist-machine-id.service
    16-persist-keys/persist-random-secret.service
    16-persist-keys/keys-persisted.target
    17-system/configure-hostname.service
    17-system/configure-networks.service
    25-persistent-partition/disk-encryption-key.service
    25-persistent-partition/encrypt-persistent.service
    25-persistent-partition/mkfs-persistent.service
    25-persistent-partition/persistent-partition.target
    40-final-node-state/final-node-state.service
    70-update-boot/update-boot.service
    85-setup-control-plane/transfer-root-key.service
    85-setup-control-plane/transfer-secureboot-cert.service
    90-node-config/update-node-config.service
    90-node-config/update-node-config.timer
  )
  for filepath in "${systemd_units[@]}"; do
    cp_tpl --raw "_systemd_units/$filepath" -d "/etc/systemd/system/$(basename "$filepath")"
  done

  if [[ $VARIANT = rpi5 ]]; then
    cp_tpl --raw _systemd_units/05-keys/rpi5-otp-secret.service -d /etc/systemd/system/rpi5-otp-secret.service
  fi
  cp_tpl --var BOOT_UUID _systemd_units/15-boot-partition/boot.mount -d /etc/systemd/system/boot.mount
  # Do not time out mounting the boot or persistent partitions
  # download-node-config blocks indefinitely until it receives a configuration
  local devpath
  for devpath in "/dev/disk/by-partuuid/$BOOT_UUID" "/dev/disk/by-partuuid/$DATA_UUID" /dev/mapper/persistent; do
    local systemd_name
    systemd_name=$(systemd-escape -p "$devpath")
    mkdir -p "/etc/systemd/system/$systemd_name.device.d"
    printf '[Unit]\nJobRunningTimeoutSec=infinity\n' >"/etc/systemd/system/$systemd_name.device.d/50-device-timeout.conf"
  done

  ln -s ../lib/upkg/.upkg/home-cluster/.upkg/.bin/step /usr/local/bin/step

  cp_tpl --raw -r --chmod=0755 \
    /usr/local/bin/boot-server-available \
    /usr/local/bin/configure-networks \
    /usr/local/bin/derive-key \
    /usr/local/bin/download-node-config \
    /usr/local/bin/get-node-config \
    /usr/local/bin/partition-disk \
    /usr/local/bin/submit-authn-key \
    /usr/local/bin/submit-node-state \
    /usr/local/bin/surrogate-key \
    /usr/local/bin/transfer-root-key \
    /usr/local/bin/transfer-secureboot-cert \
    /usr/local/bin/update-boot \
    /usr/local/bin/update-node-config

  systemctl enable \
    update-boot.service \
    keys-persisted.target \
    final-node-state.service \
    update-node-config.service \
    update-node-config.timer \

  ln -sf ../run/machine-id /etc/machine-id
  ln -sf ../../../run/machine-id /var/lib/dbus/machine-id

  cp_tpl /etc/crypttab /etc/fstab.tmp

  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id

  # Networking setup
  systemctl enable systemd-networkd
  cp_tpl /etc/hosts.tmp

  mkdir /var/lib/persistent
}
