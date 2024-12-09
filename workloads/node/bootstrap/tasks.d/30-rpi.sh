#!/usr/bin/env bash

[[ $VARIANT != rpi* ]] || PACKAGES+=(raspi-config rpi-update rpi-eeprom)
rpi() { :; }
