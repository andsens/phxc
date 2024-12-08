#!/usr/bin/env bash

PACKAGES+=(
  git # kpt
  open-iscsi nfs-common # longhorn
)

k3s() {
  install_sd_unit cluster/prepare/install-node-packages.service
  install_sd_unit cluster/prepare/configure-k3s-labels.service
  install_sd_unit cluster/prepare/configure-k3s-token.service
  install_sd_unit cluster/prepare/configure-k3s-server.service \
    --var DEFAULT_CLUSTER_CIDRS_POD_IPV4 \
    --var DEFAULT_CLUSTER_CIDRS_POD_IPV6 \
    --var DEFAULT_CLUSTER_CIDRS_SVC_IPV4 \
    --var DEFAULT_CLUSTER_CIDRS_SVC_IPV6 \
    --var DEFAULT_CLUSTER_DOMAIN
  install_sd_unit cluster/prepare/link-k3s-config@.service

  install_sd_unit cluster/k3s/etc-rancher-node.mount
  install_sd_unit cluster/k3s/var-lib-rancher-k3s.mount
  install_sd_unit cluster/k3s/k3s@.service
  install_sd_unit -e cluster/k3s/k3s.target
  install_sd_unit cluster/k3s/import-container-images.path
  install_sd_unit cluster/k3s/import-container-images.service

  install_sd_unit cluster/setup/install-control-plane-packages.service
  install_sd_unit cluster/setup/resource-ready@.service
  install_sd_unit cluster/setup/install-cilium.service
  install_sd_unit cluster/setup/configure-cilium.service
  install_sd_unit cluster/setup/apply-network-policies.service
  install_sd_unit cluster/setup/setup-coredns.service
  install_sd_unit cluster/setup/k8s-network-configured.target
  install_sd_unit cluster/setup/setup-longhorn.service
  install_sd_unit cluster/setup/setup-cert-manager.service
  install_sd_unit cluster/setup/setup-smallstep.service
  install_sd_unit cluster/setup/setup-node.service
  install_sd_unit cluster/setup/phoenix-cluster-setup.target

  cp_tpl --chmod=0755 /usr/local/bin/resource-ready

  mkdir -p /var/lib/rancher/k3s /etc/rancher/node

  cp_tpl /etc/rancher/k3s/server.yaml
  cp_tpl \
    /etc/rancher/k3s/agent.yaml \
    /etc/rancher/k3s/registry.yaml \
    /etc/rancher/k3s/config.yaml.d/shared.yaml
}
