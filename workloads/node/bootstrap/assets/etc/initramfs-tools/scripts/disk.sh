#!/usr/bin/env bash


# shellcheck disable=SC2034
DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
ESP_UUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8

get_boot_devpath() {
  local devpath=$1
  printf "/dev/%s" "$(lsblk -Jno Name "$devpath" | jq -re '.blockdevices[0].children[0].name')"
}
