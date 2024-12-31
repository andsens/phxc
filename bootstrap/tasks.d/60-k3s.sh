#!/usr/bin/env bash

PACKAGES+=(
  git # kpt
  open-iscsi nfs-common # longhorn
  python3 # kube-dns-ip.py
)

k3s() {
  mkdir -p /var/lib/rancher/k3s /etc/rancher/node
}
