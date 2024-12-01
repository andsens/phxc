#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  fdisk cryptsetup-bin # disk tooling
)

data_partition() {
  cp_tpl --var BOOT_UUID /etc/fstab.tmp
  install_sd_unit data-partition/create-data-dir@.service
  install_sd_unit data-partition/create-data-partition.service \
    --var DISK_UUID \
    --var DATA_UUID
  install_sd_unit data-partition/data-partition.target
  install_sd_unit data-partition/encrypt-data-partition.service \
    --var DATA_UUID
  install_sd_unit data-partition/mkfs-data-partition.service
  install_sd_unit data-partition/generate/copy-offline-disk-encryption-key.service
  install_sd_unit data-partition/generate/create-offline-disk-encryption-key.service
  install_sd_unit data-partition/enroll/enroll-recovery-disk-encryption-key.service \
    --var DATA_UUID
  # install_sd_unit data-partition/enroll/enroll-online-disk-encryption-key.service
  install_sd_unit data-partition/enroll/upload-recovery-disk-encryption-key.service
  install_sd_unit data-partition/enroll/unenroll-offline-disk-encryption-key.service \
    --var DATA_UUID
  if [[ $VARIANT == rpi* ]]; then
    install_sd_unit data-partition/generate/rpi-otp-disk-encryption-key.service \
      --var DEFAULT_RPI_OTP_OFFSET \
      --var DEFAULT_RPI_OTP_LENGTH \
      --var DEFAULT_RPI_OTP_KEY_DERIVATION_SUFFIX
    install_sd_unit data-partition/enroll/rpi-init-otp.service \
      --var DEFAULT_NODE_DISK_ENCRYPTION \
      --var DEFAULT_RPI_OTP_OFFSET \
      --var DEFAULT_RPI_OTP_LENGTH
    install_sd_unit data-partition/enroll/enroll-rpi-otp-disk-encryption-key.service \
      --var DATA_UUID \
      --var DEFAULT_NODE_DISK_ENCRYPTION \
      --var DEFAULT_RPI_OTP_OFFSET \
      --var DEFAULT_RPI_OTP_LENGTH \
      --var DEFAULT_RPI_OTP_KEY_DERIVATION_SUFFIX
    systemctl enable rpi-init-otp.service
  else
    install_sd_unit data-partition/generate/tpm2-crypttab.service
    install_sd_unit data-partition/enroll/enroll-tpm2-disk-encryption-key.service \
      --var DATA_UUID \
      --var DEFAULT_NODE_DISK_ENCRYPTION
  fi
  install_sd_unit data-partition/enroll/disk-encryption-keys-enrolled.target

  systemctl enable \
    disk-encryption-keys-enrolled.target \
    unenroll-offline-disk-encryption-key.service

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
