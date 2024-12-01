#!/usr/bin/env bash

update_boot() {
  install_sd_unit update-boot/update-boot.service
  install_sd_unit update-boot/update-boot.timer
  cp_tpl --chmod=0755 \
    /usr/local/bin/update-boot \
    /usr/local/bin/try-reboot
  systemctl enable update-boot.service update-boot.timer
}
