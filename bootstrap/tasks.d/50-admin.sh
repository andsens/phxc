#!/usr/bin/env bash

PACKAGES+=(sudo adduser)
! $DEBUG || PACKAGES+=(less nano bsdextrautils tree psmisc dnsutils lsof netcat-openbsd)

admin() {
  chmod 0440 /etc/sudoers.d/20_admin_nopass
  useradd -m -s /bin/bash -u 1000 admin
  adduser admin adm
  adduser admin sudo
  mkdir /home/admin/.ssh
  if [[ -e /workspace/cluster.json ]]; then
    info "Copying admin ssh key to /home/admin/.ssh/authorized_keys"
    jq -r '.admin["ssh-keys"][]' /workspace/cluster.json > /home/admin/.ssh/authorized_keys
    local pwhash
    ! pwhash=$(get-config /workspace/cluster.json admin.pwhash) || usermod -p "$pwhash" admin
  fi
  usermod -L root
  chown -R admin:admin /home/admin/.ssh
  chmod -R u=rwX,go=rX /home/admin/.ssh
}
