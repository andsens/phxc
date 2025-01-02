#!/usr/bin/env bash

if [[ $VARIANT != rpi* ]]; then
  PACKAGES+=(
    mokutil # For enrolling the secureboot cert
  )
fi

secureboot() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/enroll-mok.service
  else
    rm /etc/systemd/system/enroll-rpi-sb-cert.service
  fi
}
