#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
)

data_partition() {
  cp_tpl --var BOOT_UUID /etc/fstab.tmp
  install_sd_unit data-partition/create-data-dir@.service
  install_sd_unit data-partition/expand-data-partition.service \
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
  install_sd_unit -e data-partition/enroll/unenroll-offline-disk-encryption-key.service \
    --var DATA_UUID
  if [[ $VARIANT == rpi* ]]; then
    install_sd_unit data-partition/generate/rpi-otp-disk-encryption-key.service
    install_sd_unit -e data-partition/enroll/rpi-init-otp.service
    install_sd_unit data-partition/enroll/enroll-rpi-otp-disk-encryption-key.service \
      --var DATA_UUID
  else
    install_sd_unit data-partition/generate/tpm2-crypttab.service
    install_sd_unit data-partition/enroll/enroll-tpm2-disk-encryption-key.service \
      --var DATA_UUID
  fi
  install_sd_unit -e data-partition/enroll/disk-encryption-keys-enrolled.target

  cp_tpl --var DATA_UUID /etc/crypttab

  mkdir /var/lib/phxc
}
