#!/usr/bin/env bash

PACKAGES+=(
  git # kpt dep
  open-iscsi nfs-common # longhorn deps
  tpm2-tools openssl xxd curl systemd-timesyncd # Remote attestation for cluster authentication
)

k3s() {
  mkdir -p /var/lib/rancher/k3s/agent/containerd
  cp_tpl /etc/rancher/k3s/server.yaml
  cp_tpl --raw \
    /etc/systemd/system/cluster-auth.service \
    /etc/systemd/system/configure-k3s.service \
    /etc/systemd/system/setup-persistent.service \
    /etc/systemd/system/var-lib-rancher-k3s-agent-containerd.mount \
    /etc/systemd/system/var-lib-longhorn.mount \
    /etc/systemd/system/etc-rancher-node.mount \
    /etc/systemd/system/workload-ready@.service \
    /etc/systemd/system/workload-ready@.target \
    /etc/systemd/system/k3s.target \
    /etc/systemd/system/k3s@.service \
    /etc/rancher/k3s/agent.yaml \
    /etc/rancher/k3s/registry.yaml \
    /etc/rancher/k3s/config.yaml.d/shared.yaml \
    /etc/systemd/system/install-cilium.service \
    /etc/systemd/system/pull-external-images.service \
    /etc/systemd/system/apply-all-manifests.service \
    /etc/systemd/system/import-container-images.service \
    /etc/systemd/system/import-container-images.path

  systemctl enable \
    systemd-timesyncd.service \
    cluster-auth.service \
    setup-persistent.service \
    var-lib-rancher-k3s-agent-containerd.mount \
    var-lib-longhorn.mount \
    etc-rancher-node.mount \
    k3s.target \
    install-cilium.service \
    pull-external-images.service \
    apply-all-manifests.service \
    import-container-images.path
}
