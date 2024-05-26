#!/usr/bin/env bash

PACKAGES+=(wget ca-certificates)

k8s_node() {
  # shellcheck disable=2054
  k3s_exec_flags=(
    --disable-apiserver-lb
    --snapshotter=stargz
  )

  INSTALL_K3S_SKIP_START=true \
  K3S_TOKEN=$CLUSTER_K3STOKEN \
  INSTALL_K3S_EXEC="${k3s_exec_flags[*]}" \
  K3S_URL=https://[$MACHINES_K8SMASTER_FIXEDIPV6]:6443 \
  bash <(wget -qO- https://get.k3s.io) || true # systemctl daemon-reload fails because dbus is not started. Ignore. It's the last action in the install script

  # /etc/rancher/k3s is created on master nodes but not on agents for some reason
  mkdir -p /etc/rancher/k3s
}
