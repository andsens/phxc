#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
)

if [[ $VARIANT != rpi* ]]; then
  PACKAGES+=(
    libtss2-rc0 libtss2-esys-3.0.2-0t64 # For TPM based disk encryption
  )
fi

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/enroll-tpm2-key.service \
       /etc/crypttab.tpm2
  else
    rm /etc/systemd/system/init-rpi-otp.service \
       /etc/systemd/system/enroll-rpi-otp-key.service \
       /etc/systemd/system/generate-rpi-otp-key.service \
       /etc/crypttab.rpi-otp
  fi
  chmod 0600 /etc/phxc/disk-encryption.static.key
}
