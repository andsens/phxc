#!/usr/bin/env bash

update_boot() {
  cp_tpl --var BOOT_UUID /etc/fstab.tmp
  install_sd_unit 70-update-boot/update-boot.service
  cp_tpl --chmod=0755 /usr/local/bin/update-boot
  systemctl enable update-boot.service
}
