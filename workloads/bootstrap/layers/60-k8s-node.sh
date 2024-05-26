#!/usr/bin/env bash

PACKAGES+=(wget ca-certificates)

k8s_node() {
  # systemctl daemon-reload fails because dbus is not started. Ignore. It's the last action in the install script
  INSTALL_K3S_SKIP_START=true \
  K3S_TOKEN=$CLUSTER_K3STOKEN \
  K3S_URL=https://$MACHINES_K8SMASTER_HOSTNAME:6443 \
  bash <(wget -qO- https://get.k3s.io) || true

  # /etc/rancher/k3s is created on master nodes but not on agents for some reason
  mkdir -p /etc/rancher/k3s
}
