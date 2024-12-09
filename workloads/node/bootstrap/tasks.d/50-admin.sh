#!/usr/bin/env bash

PACKAGES+=(
  sudo adduser
)
if $DEBUG; then
  PACKAGES+=(less nano bsdextrautils tree psmisc dnsutils)
fi

admin() {
  cp_tpl /etc/sysctl.d/10-kprint.conf
  useradd -m -s /bin/bash -u 1000 admin
  adduser admin adm
  adduser admin sudo
  mkdir /home/admin/.ssh
  if [[ -e /workspace/embed-configs ]]; then
    usermod -p "$(yq -r '.admin["pwhash"]' /workspace/embed-configs/cluster.yaml)" admin
    yq -r '.admin["ssh-key"]' /workspace/embed-configs/cluster.yaml > /home/admin/.ssh/authorized_keys
    if $DEBUG; then
      usermod -p "$(yq -r '.admin["pwhash"]' /workspace/embed-configs/cluster.yaml)" root
    else
      usermod -L root
    fi
  else
    usermod -L root
  fi
  chown -R admin:admin /home/admin/.ssh
  chmod -R u=rwX,go=rX /home/admin/.ssh
}
