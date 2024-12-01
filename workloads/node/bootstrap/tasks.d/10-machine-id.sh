#!/usr/bin/env bash

machine_id() {
  install_sd_unit config/persist-machine-id.service

  ln -sf ../run/machine-id /etc/machine-id
  ln -sf ../../../run/machine-id /var/lib/dbus/machine-id

  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id
}
