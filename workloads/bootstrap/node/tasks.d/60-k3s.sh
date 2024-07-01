#!/usr/bin/env bash

PACKAGES+=(
  git # kpt dep
  open-iscsi nfs-common # longhorn deps
)

k3s() {
  cp_tpl /etc/rancher/k3s/server.yaml
  cp_tpl --raw \
    /etc/systemd/system/k3s@.target \
    /etc/rancher/k3s/agent.yaml \
    /etc/rancher/k3s/registry.yaml \
    /etc/systemd/system/k3s.service \
    /etc/systemd/system/k3s@.service \
    /etc/systemd/system/install-cilium.service \
    /etc/systemd/system/pull-external-images.service \
    /etc/systemd/system/apply-all-manifests.service \
    /etc/systemd/system/import-container-images.service \
    /etc/systemd/system/import-container-images.path

  systemctl enable \
    install-cilium.service \
    pull-external-images.service \
    apply-all-manifests.service \
    import-container-images.path \
    k3s.service
}
