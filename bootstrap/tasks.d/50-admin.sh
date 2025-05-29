#!/usr/bin/env bash

admin_pre_install() {
  PACKAGES+=(sudo)
  ! $DEBUG || PACKAGES+=(less nano bsdextrautils tree psmisc dnsutils lsof netcat-openbsd)
  PACKAGES_TMP+=(adduser)
}

admin() {
  chmod 0440 /etc/sudoers.d/20_admin_nopass
  useradd -m -s /bin/bash -u 1000 admin
  adduser admin adm
  adduser admin sudo
  mkdir /home/admin/.ssh

  if [[ -e /workspace/admin-credentials/authorized_keys ]]; then
    cp /workspace/admin-credentials/authorized_keys /home/admin/.ssh/authorized_keys
  fi
  if pwhash=$(grep -m1 admin /workspace/admin-credentials/shadow 2>/dev/null | cut -d: -f2); then
    usermod -p "$pwhash" admin
    ! $DEBUG || usermod -p "$pwhash" root
  fi
  if $DEBUG; then
    usermod -U root
  else
    usermod -L root
  fi
  chown -R admin:admin /home/admin/.ssh
  chmod -R u=rwX,go=rX /home/admin/.ssh
}
