#!/usr/bin/env bash

PACKAGES+=(sudo "$(basename "${ADMIN_SHELL:?}")")
if $DEBUG; then
  PACKAGES+=(less nano bsdextrautils)
fi

admin() {
  if $DEBUG; then
    usermod -p "${ADMIN_PWHASH:?}" root
  else
    usermod -L root
  fi
  useradd -m -s "$ADMIN_SHELL" -u "${ADMIN_UID:?}" "${ADMIN_USERNAME:?}"
  usermod -p "${ADMIN_PWHASH:?}" "$ADMIN_USERNAME"
  adduser "$ADMIN_USERNAME" adm
  adduser "$ADMIN_USERNAME" sudo
  userdir=$(getent passwd "$ADMIN_USERNAME" | cut -d: -f6 )

  mkdir "$userdir/.ssh"
  local i key
  for ((i=0;;i++)); do
    key=ADMIN_AUTHORIZED_KEYS_$i
    [[ -n ${!key} ]] || break
    printf "%s\n" "${!key}" >> "$userdir/.ssh/authorized_keys"
  done
  chown -R "$ADMIN_USERNAME:$ADMIN_USERNAME" "$userdir/.ssh"
  chmod -R u=rwX,go=rX "$userdir/.ssh"
}
