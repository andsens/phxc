#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  fdisk cryptsetup-bin # disk tooling
)

data_partition() {
  install_sd_unit 25-data-partition/disk-encryption-key.service
  install_sd_unit 25-data-partition/encrypt-data.service
  install_sd_unit 25-data-partition/mkfs-data.service
  install_sd_unit 25-data-partition/data-partition.target
  [[ $VARIANT != rpi5 ]] || install_sd_unit rpi5-otp-secret.service

  local devpath
  for devpath in "/dev/disk/by-partuuid/$DATA_UUID" /dev/mapper/data; do
    local systemd_name
    systemd_name=$(systemd-escape -p "$devpath")
    mkdir -p "/etc/systemd/system/$systemd_name.device.d"
    printf '[Unit]\nJobRunningTimeoutSec=infinity\n' >"/etc/systemd/system/$systemd_name.device.d/50-device-timeout.conf"
  done

  cp_tpl --var DATA_UUID /etc/crypttab

  mkdir /var/lib/phxc
}
