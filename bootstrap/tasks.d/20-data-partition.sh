#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
  dropbear # for entering the recovery key
)

if [[ $VARIANT != rpi* ]]; then
  PACKAGES+=(
    libtss2-rc0 libtss2-esys-3.0.2-0t64 xxd # For TPM based disk encryption
  )
fi

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/crypttab.tpm2
  else
    rm /etc/systemd/system/diskenc-rpi-otp.service \
       /etc/crypttab.rpi-otp
  fi
  # Mask systemd-ask-password-console.path so that only user authenticated via SSH can enter a password
  systemctl mask systemd-ask-password-console.path

  rm /etc/dropbear/dropbear_*_host_key*
}
