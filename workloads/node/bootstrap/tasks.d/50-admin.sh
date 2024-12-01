#!/usr/bin/env bash

PACKAGES+=(
  sudo adduser
)
if $DEBUG; then
  PACKAGES+=(less nano bsdextrautils)
fi

admin() {
  useradd -m -s /bin/bash -u 1000 admin
  [[ -z $ADMIN_PWHASH ]] || \
    usermod -p "$ADMIN_PWHASH" admin
  adduser admin adm
  adduser admin sudo
  mkdir /home/admin/.ssh
  [[ -z $ADMIN_SSH_KEY ]] || \
    printf "%s\n" "$ADMIN_SSH_KEY" > /home/admin/.ssh/authorized_keys
  chown -R admin:admin /home/admin/.ssh
  chmod -R u=rwX,go=rX /home/admin/.ssh

  if $DEBUG && [[ -n $ADMIN_PWHASH ]]; then
    usermod -p "$ADMIN_PWHASH" root
  else
    usermod -L root
  fi
}
