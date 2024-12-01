#!/usr/bin/env bash

PACKAGES+=(
  open-iscsi nfs-common # longhorn
)

k3s() {
  install_sd_unit cluster/prepare/install-control-plane-packages.service
  install_sd_unit cluster/prepare/configure-k3s-labels.service
  install_sd_unit cluster/prepare/configure-k3s-token.service
  install_sd_unit cluster/prepare/configure-k3s-server.service \
    --var DEFAULT_CLUSTER_CIDRS_POD_IPV4 \
    --var DEFAULT_CLUSTER_CIDRS_POD_IPV6 \
    --var DEFAULT_CLUSTER_CIDRS_SVC_IPV4 \
    --var DEFAULT_CLUSTER_CIDRS_SVC_IPV6 \
    --var DEFAULT_CLUSTER_DOMAIN
  install_sd_unit cluster/k3s/k3s.target
  install_sd_unit cluster/k3s/k3s@.service --var DEFAULT_NODE_K3S_MODE
  install_sd_unit cluster/prepare/etc-rancher-node.mount
  install_sd_unit cluster/prepare/var-lib-rancher-k3s.mount
  install_sd_unit cluster/prepare/var-lib-longhorn.mount
  install_sd_unit cluster/setup/install-cilium.service
  install_sd_unit cluster/setup/apply-all-manifests.service
  install_sd_unit cluster/k3s/import-container-images.path
  install_sd_unit cluster/k3s/import-container-images.service

  install_sd_unit cluster/k3s/resource-ready@.service
  cp_tpl --chmod=0755 /usr/local/bin/resource-ready

  cp_tpl /etc/rancher/k3s/server.yaml
  cp_tpl \
    /etc/rancher/k3s/agent.yaml \
    /etc/rancher/k3s/registry.yaml \
    /etc/rancher/k3s/config.yaml.d/shared.yaml
  systemctl enable k3s.target
}
