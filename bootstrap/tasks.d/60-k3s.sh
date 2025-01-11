#!/usr/bin/env bash

PACKAGES+=(
  open-iscsi nfs-common # longhorn
)

k3s() {
  chmod 0750 /var/lib/kubelet
}
