#!/usr/bin/env bash

if [[ $VARIANT != rpi* ]]; then
  PACKAGES+=(
    mokutil # For enrolling the secureboot cert
    libtss2-rc0
    libtss2-esys-3.0.2-0t64
  )
fi

secureboot() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/enroll-mok.service
  else
    rm /etc/systemd/system/enroll-rpi-sb-cert.service
  fi
}
