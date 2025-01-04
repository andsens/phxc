#!/usr/bin/env bash

PACKAGES+=(
  git # kpt
  open-iscsi nfs-common # longhorn
)

k3s() {
  chmod 0750 /var/lib/kubelet
}
