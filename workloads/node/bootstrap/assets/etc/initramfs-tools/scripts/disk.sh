#!/usr/bin/env bash


DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
ESP_UUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8

find_disk() {
  local devpaths=()
  readarray -t -d $'\n' devpaths < <(lsblk -Jndo PTUUID,NAME -a | jq -r --arg disk_uuid $DISK_UUID '.blockdevices[] | select(.ptuuid==$disk_uuid) | "/dev/\(.name)"')
  if [[ ${#devpaths[@]} -eq 1 ]]; then
    info "Disk found at /dev/%s" "${devpaths[0]}"
    printf "/dev/%s" "${devpaths[0]}"
  elif [[ ${#devpaths[@]} -gt 1 ]]; then
    fatal "Found multiple disks marked with the UUID '%s'" "$DISK_UUID"
  else
    fatal "No disk with the UUID '%s' found" "$DISK_UUID"
  fi
}

get_boot_devpath() {
  local devpath=$1
  printf "/dev/%s" "$(lsblk -Jno Name "$devpath" | jq -re '.blockdevices[0].children[0].name')"
}
