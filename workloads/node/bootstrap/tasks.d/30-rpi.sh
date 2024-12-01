#!/usr/bin/env bash

case $VARIANT in
  amd64) ;;
  arm64) ;;
  rpi*) PACKAGES+=(raspi-config rpi-update rpi-eeprom) ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

rpi() {
  :
}
