#!/usr/bin/env bash

data_partition_pre_copy() {
  FILES_ENVSUBST+=(
    /usr/lib/dracut/modules.d/99phxc/crypttab
    /usr/lib/dracut/modules.d/99phxc/repart.d/10-boot.conf
    /usr/lib/dracut/modules.d/99phxc/repart.d/60-data.conf
  )
  if [[ $VARIANT = rpi* ]]; then
    FILES_EXCLUDE+=(
      /etc/systemd/system/unenroll-tpm2-keys.service
    )
  else
    FILES_EXCLUDE+=(
      /usr/local/sbin/rpi-otp-init
      /usr/local/sbin/rpi-otp-derive-key
    )
  fi
}

data_partition_pre_install() {
  PACKAGES+=(
    systemd-cryptsetup # encrypted data
    cryptsetup-bin # disk tooling
  )
  PACKAGES_TMP+=(
    systemd-repart # partition setup
  )
  if [[ $VARIANT != rpi* ]]; then
    PACKAGES+=(
      libtss2-rc0 libtss2-esys-3.0.2-0t64 xxd # For TPM based disk encryption
    )
  fi
}

data_partition_cleanup() {
  rm /etc/dropbear/dropbear_*_host_key*
}
