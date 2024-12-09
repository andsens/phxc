#!/usr/bin/env bash

case $VARIANT in
  amd64) PACKAGES+=(systemd-boot) ;;
  arm64) PACKAGES+=(systemd-boot) ;;
  rpi*) ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

rpi() {
  :
}

update_boot() {
  install_sd_unit -e update-boot/update-boot.service
  install_sd_unit -e update-boot/update-boot.timer
  install_sd_unit -e update-boot/switch-boot.service
  install_sd_unit -e update-boot/clear-lease.service
  cp_tpl --chmod=0755 \
    /usr/local/bin/update-boot \
    /usr/local/bin/try-reboot \
    /usr/local/bin/switch-boot
}
