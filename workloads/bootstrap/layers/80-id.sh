#!/usr/bin/env bash

id() {
  : "${MACHINE_HOSTNAME:?}" "${MACHINE_UUID:?}"
  cp_tpl /etc/hostname
  cp_tpl /var/lib/dbus/machine-id
  cp_tpl /etc/machine-id
}
