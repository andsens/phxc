#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  cryptsetup-bin # disk tooling
)
PACKAGES_TMP+=(
  systemd-repart # partition setup
)

FILES_ENVSUBST+=(
  /usr/lib/dracut/modules.d/99phxc/crypttab
  /usr/lib/dracut/modules.d/99phxc/repart.d/10-esp.conf
  /usr/lib/dracut/modules.d/99phxc/repart.d/60-data.conf
)

if [[ $VARIANT != rpi* ]]; then
  PACKAGES+=(
    libtss2-rc0 libtss2-esys-3.0.2-0t64 xxd # For TPM based disk encryption
  )
fi

data_partition() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/unenroll-tpm2-keys.service
  else
    rm /usr/local/bin/rpi-otp-disk-encryption-key \
       /usr/local/bin/phxc-rpi
  fi

  rm /etc/dropbear/dropbear_*_host_key*
}
