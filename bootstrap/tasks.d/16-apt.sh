#!/usr/bin/env bash

apt() {
  systemctl disable \
    dpkg-db-backup \
    apt-daily.timer \
    apt-daily.service \
    apt-daily-upgrade.timer \
    apt-daily-upgrade.service
  systemctl mask \
    apt-daily.timer \
    apt-daily.service \
    apt-daily-upgrade.timer \
    apt-daily-upgrade.service
}
