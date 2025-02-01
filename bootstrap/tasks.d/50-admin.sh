#!/usr/bin/env bash

PACKAGES+=(sudo)
! $DEBUG || PACKAGES+=(less nano bsdextrautils tree psmisc dnsutils lsof netcat-openbsd)
PACKAGES_TMP+=(adduser)

admin() {
  chmod 0440 /etc/sudoers.d/20_admin_nopass
  useradd -m -s /bin/bash -u 1000 admin
  adduser admin adm
  adduser admin sudo
  mkdir /home/admin/.ssh

  if [[ -e /workspace/cluster.json ]]; then
    jq -r '.admin["ssh-keys"][]' /workspace/cluster.json >/home/admin/.ssh/authorized_keys
    if pwhash=$(jq -re .admin.pwhash /workspace/cluster.json); then
      usermod -p "$pwhash" admin
      ! $DEBUG || usermod -p "$pwhash" root
    fi
  fi
  if $DEBUG; then
    usermod -U root
  else
    usermod -L root
  fi
  chown -R admin:admin /home/admin/.ssh
  chmod -R u=rwX,go=rX /home/admin/.ssh
}
