#!/usr/bin/env bash

PACKAGES+=(sudo "$(basename "${ADMIN_SHELL:?}")")

admin() {
  usermod -L root
  useradd -m -s "$ADMIN_SHELL" -u "${ADMIN_UID:?}" "${ADMIN_USERNAME:?}"
  usermod -p "${ADMIN_PWHASH:?}" "$ADMIN_USERNAME"
  adduser "$ADMIN_USERNAME" adm
  adduser "$ADMIN_USERNAME" sudo
  userdir=$(getent passwd "$ADMIN_USERNAME" | cut -d: -f6 )

  mkdir "$userdir/.ssh"
  [[ -z $ADMIN_AUTHORIZED_KEYS ]] || printf "%s\n" "$ADMIN_AUTHORIZED_KEYS" > "$userdir/.ssh/authorized_keys"
  chown -R "$ADMIN_USERNAME:$ADMIN_USERNAME" "$userdir/.ssh"
  chmod -R u=rwX,go=rX "$userdir/.ssh"

  if [[ -n $NFS_SHARES_ADMIN_HOME_ADDR ]]; then
    systemd_unitname=$(systemd-escape -p --suffix=mount "/home/$ADMIN_USERNAME")
    cp_tpl /etc/systemd/system/admin-home.mount -d "/etc/systemd/system/$systemd_unitname"
    systemctl enable "$systemd_unitname"
  fi
}
