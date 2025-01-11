#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
)

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/enroll-tpm2-key.service \
       /etc/crypttab.tpm2
  else
    rm /etc/systemd/system/init-rpi-otp.service \
       /etc/systemd/system/enroll-rpi-otp-key.service \
       /etc/crypttab.rpi-otp
  fi
  chmod 0600 /etc/phxc/disk-encryption.static.key
}
