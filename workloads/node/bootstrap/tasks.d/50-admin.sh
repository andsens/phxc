#!/usr/bin/env bash

PACKAGES+=(
  sudo adduser
)
if $DEBUG; then
  PACKAGES+=(less nano bsdextrautils)
fi

admin() {
  useradd -m -s /bin/bash -u 1000 admin
  adduser admin adm
  adduser admin sudo
  mkdir /home/admin/.ssh
  if [[ -e /workspace/cluster-yaml ]]; then
    usermod -p "$(yq -r '.admin["pwhash"]' /workspace/cluster-yaml/cluster.yaml)" admin
    yq -r '.admin["ssh-key"]' /workspace/cluster-yaml/cluster.yaml > /home/admin/.ssh/authorized_keys
    if $DEBUG; then
      usermod -p "$(yq -r '.admin["pwhash"]' /workspace/cluster-yaml/cluster.yaml)" root
    else
      usermod -L root
    fi
  else
    usermod -L root
  fi
  chown -R admin:admin /home/admin/.ssh
  chmod -R u=rwX,go=rX /home/admin/.ssh
}
