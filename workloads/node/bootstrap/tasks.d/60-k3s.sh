#!/usr/bin/env bash

PACKAGES+=(
  git # kpt
  open-iscsi nfs-common # longhorn
)

k3s() {
  chmod 0755 /usr/local/bin/resource-ready
  mkdir -p /var/lib/rancher/k3s /etc/rancher/node
}
