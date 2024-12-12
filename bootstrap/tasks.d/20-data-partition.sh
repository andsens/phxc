#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
)

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/tpm2-crypttab.service \
       /etc/systemd/system/enroll-tpm2-disk-encryption-key.service
  else
    rm /etc/systemd/system/rpi-otp-disk-encryption-key.service \
       /etc/systemd/system/rpi-init-otp.service \
       /etc/systemd/system/enroll-rpi-otp-disk-encryption-key.service
  fi
  mkdir /var/lib/phxc
}
