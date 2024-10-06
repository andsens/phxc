#!/usr/bin/env bash

PACKAGES+=(
  git # kpt dep
  open-iscsi nfs-common # longhorn deps
)

k3s() {
  local filepath systemd_units=(
    80-k3s/apply-all-manifests.service
    80-k3s/configure-k3s.service
    80-k3s/import-container-images.path
    80-k3s/import-container-images.service
    80-k3s/k3s@.service
    80-k3s/k3s.target
    80-k3s/resource-ready@.service
    80-k3s/etc-rancher-node.mount
    80-k3s/var-lib-longhorn.mount
    80-k3s/var-lib-rancher-k3s.mount
    80-k3s/create-persistent-dir@.service
  )
  for filepath in "${systemd_units[@]}"; do
    cp_tpl --raw "_systemd_units/$filepath" -d "/etc/systemd/system/$(basename "$filepath")"
  done

  cp_tpl --raw --chmod=0755 \
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
  cp_tpl \
    --var CLUSTER_CIDRS_PODIPV4 --var CLUSTER_CIDRS_PODIPV6 --var CLUSTER_CILIUM_K8SSERVICEHOST --var CLUSTER_CIDRS_SVCIPV6 \
    _systemd_units/80-k3s/install-cilium.service -d /etc/systemd/system/install-cilium.service

  cp_tpl /etc/rancher/k3s/server.yaml
  cp_tpl --raw \
    /etc/rancher/k3s/agent.yaml \
    /etc/rancher/k3s/registry.yaml \
    /etc/rancher/k3s/config.yaml.d/shared.yaml
  systemctl enable \
    k3s.target
}
