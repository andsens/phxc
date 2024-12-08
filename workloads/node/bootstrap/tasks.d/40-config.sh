#!/usr/bin/env bash

PACKAGES+=(
  yq # For converting config files to json
  python3-jsonschema # For validating config files
)

config() {
  cp_tpl -r /usr/local/lib/phxc/schemas
  cp_tpl --chmod 0755 /usr/local/bin/get-config
  mkdir /etc/phxc
  install_sd_unit config/copy-cluster-config.service

  install_sd_unit -e config/persist-machine-id.service
  install_sd_unit -e config/setup-admin-credentials.service

  install_sd_unit config/persist-machine-id.service
  ln -sf ../run/machine-id /etc/machine-id
  ln -sf ../../../run/machine-id /var/lib/dbus/machine-id
  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id

  cp_tpl /etc/systemd/system.conf.d/phxc-packages.conf
  cp_tpl /etc/profile.d/phxc-packages.sh
}
