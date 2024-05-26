#!/usr/bin/env bash

PACKAGES+=(overlayroot)

root() {
  cp_tpl /etc/overlayroot.conf

  systemctl disable fstrim e2scrub_all e2scrub_reap dpkg-db-backup apt-daily.timer apt-daily-upgrade.timer
  systemctl mask apt-daily.service
}
