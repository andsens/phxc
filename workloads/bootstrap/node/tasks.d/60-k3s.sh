#!/usr/bin/env bash

PACKAGES+=(
  wget ca-certificates
  git # kpt dep
  open-iscsi nfs-common # longhorn deps
)

k3s() {
  local cmd
  for cmd in k3s kubectl crictl ctr; do
    upkg add -gp "$cmd" 'https://github.com/k3s-io/k3s/releases/download/v1.30.0%2Bk3s1/k3s' e4b85e74d7be314f39e033142973cc53619f4fbaff3639a420312f20dea12868
  done
  mkdir -p /etc/rancher/k3s/config.yaml.d

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
