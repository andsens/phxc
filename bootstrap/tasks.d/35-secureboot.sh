#!/usr/bin/env bash

secureboot() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/enroll-mok.service
  else
    rm /etc/systemd/system/enroll-rpi-sb-cert.service
  fi
}
