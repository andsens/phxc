#!/usr/bin/env bash

PACKAGES+=(
  sudo adduser
)
if $DEBUG; then
  PACKAGES+=(less nano bsdextrautils)
fi

admin() {
  if $DEBUG; then
    :
    # usermod -p "${ADMIN_PWHASH:?}" root
  else
    usermod -L root
  fi
  useradd -m -s /bin/bash -u 1000 admin
  # usermod -p "${ADMIN_PWHASH:?}" admin
  adduser admin adm
  adduser admin sudo
  userdir=$(getent passwd admin | cut -d: -f6)

  mkdir "$userdir/.ssh"
  local i key
  for ((i=0;;i++)); do
    key=ADMIN_AUTHORIZED_KEYS_$i
    [[ -n ${!key} ]] || break
    printf "%s\n" "${!key}" >> "$userdir/.ssh/authorized_keys"
  done
  chown -R admin:admin "$userdir/.ssh"
  chmod -R u=rwX,go=rX "$userdir/.ssh"
}
