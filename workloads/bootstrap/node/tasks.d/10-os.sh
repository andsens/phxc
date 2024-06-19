#!/usr/bin/env bash

BPACKAGES+=(systemd adduser)
PACKAGES+=(systemd adduser)

os() {
  systemctl disable fstrim e2scrub_all e2scrub_reap dpkg-db-backup apt-daily.timer apt-daily-upgrade.timer
  systemctl mask apt-daily.service apt-daily-upgrade.service
}
