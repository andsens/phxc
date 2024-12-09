#!/usr/bin/env bash

PACKAGES+=(
  git # kpt
  open-iscsi nfs-common # longhorn
)

k3s() {
  mkdir -p /var/lib/rancher/k3s /etc/rancher/node
}
