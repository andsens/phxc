#!/usr/bin/env bash

[[ $VARIANT != rpi* ]] || PACKAGES+=(raspi-config rpi-update rpi-eeprom)
rpi() {
  [[ $VARIANT = rpi* ]] || rm /usr/local/bin/phxc-rpi
}
