#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
)

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/tpm2-crypttab.service \
       /etc/systemd/system/enroll-diskenc-tpm2-key.service
  else
    rm /etc/systemd/system/diskenc-rpi-otp-key.service \
       /etc/systemd/system/init-rpi-otp.service \
       /etc/systemd/system/enroll-diskenc-rpi-otp-key.service
  fi
}
