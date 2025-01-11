#!/usr/bin/env bash

[[ $VARIANT != rpi* ]] || PACKAGES+=(raspi-config rpi-update rpi-eeprom)
rpi() {
  [[ $VARIANT = rpi* ]] || rm /etc/systemd/system/enroll-rpi-sb-cert.service
}
