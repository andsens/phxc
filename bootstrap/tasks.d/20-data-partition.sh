#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  parted cryptsetup-bin # disk tooling
  dropbear # for entering the recovery key
)

FILES_ENVSUBST+=(/etc/crypttab.nopw)
if [[ $VARIANT = rpi* ]]; then
  FILES_ENVSUBST+=(/etc/crypttab.rpi-otp)
else
  PACKAGES+=(
    libtss2-rc0 libtss2-esys-3.0.2-0t64 xxd # For TPM based disk encryption
  )
  FILES_ENVSUBST+=(/etc/crypttab.tpm2)
fi

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/unenroll-tpm2-keys.service \
       /etc/crypttab.tpm2
  else
    rm /etc/systemd/system/diskenc-rpi-otp.service \
       /etc/crypttab.rpi-otp
  fi


  # Mask systemd-ask-password-console.path so that only user authenticated via SSH can enter a password
  systemctl mask systemd-ask-password-console.path

  rm /etc/dropbear/dropbear_*_host_key*
}
