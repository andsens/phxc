#!/usr/bin/env bash

PACKAGES+=(
  open-iscsi nfs-common # longhorn
)

k3s() {
  install_sd_unit 80-k3s/apply-all-manifests.service
  install_sd_unit 80-k3s/configure-k3s.service
  install_sd_unit 80-k3s/import-container-images.path
  install_sd_unit 80-k3s/import-container-images.service
  install_sd_unit 80-k3s/k3s@.service
  install_sd_unit 80-k3s/k3s.target
  install_sd_unit 80-k3s/resource-ready@.service
  install_sd_unit 80-k3s/etc-rancher-node.mount
  install_sd_unit 80-k3s/var-lib-longhorn.mount
  install_sd_unit 80-k3s/var-lib-rancher-k3s.mount
  install_sd_unit 80-k3s/create-data-dir@.service

  cp_tpl --chmod=0755 \
    /usr/local/bin/configure-k3s \
    /usr/local/bin/resource-ready \
    /usr/local/bin/import-container-images
  mkdir -p /etc/systemd/resolved.conf.d
  export \
    CLUSTER_DOMAIN \
    CLUSTER_COREDNS_SVC_FIXEDIPV4 CLUSTER_COREDNS_SVC_FIXEDIPV6 \
    CLUSTER_CIDRS_PODIPV4 CLUSTER_CIDRS_PODIPV6 \
    CLUSTER_CIDRS_SVCIPV6 \
    CLUSTER_CILIUM_K8SSERVICEHOST
  cp_tpl \
    --var CLUSTER_DOMAIN --var CLUSTER_COREDNS_SVC_FIXEDIPV4 --var CLUSTER_COREDNS_SVC_FIXEDIPV6 \
    /etc/systemd/resolved.conf.d/cluster-domain.conf
  install_sd_unit \
    --var CLUSTER_CIDRS_PODIPV4 --var CLUSTER_CIDRS_PODIPV6 --var CLUSTER_CILIUM_K8SSERVICEHOST --var CLUSTER_CIDRS_SVCIPV6 \
    80-k3s/install-cilium.service

  cp_tpl \
    --var CLUSTER_CIDRS_PODIPV4 \
    --var CLUSTER_CIDRS_PODIPV6 \
    --var CLUSTER_CIDRS_SVCIPV4 \
    --var CLUSTER_CIDRS_SVCIPV6 \
    --var CLUSTER_DOMAIN \
    /etc/rancher/k3s/server.yaml
  cp_tpl \
    /etc/rancher/k3s/agent.yaml \
    /etc/rancher/k3s/registry.yaml \
    /etc/rancher/k3s/config.yaml.d/shared.yaml
  systemctl enable \
    k3s.target
}
