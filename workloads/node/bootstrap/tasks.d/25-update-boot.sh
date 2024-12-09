#!/usr/bin/env bash

case $VARIANT in
  amd64) PACKAGES+=(systemd-boot) ;;
  arm64) PACKAGES+=(systemd-boot) ;;
  rpi*) ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

update_boot() {
  chmod 0755 /usr/local/bin/update-boot \
             /usr/local/bin/try-reboot \
             /usr/local/bin/switch-boot
}
