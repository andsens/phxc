#!/usr/bin/env bash

PACKAGES+=(systemd adduser)

os() {
  systemctl disable dpkg-db-backup apt-daily.timer apt-daily-upgrade.timer
  systemctl mask apt-daily.service apt-daily-upgrade.service
}
