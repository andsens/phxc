#!/usr/bin/env bash

PACKAGES+=(wget ca-certificates)

k3s() {
  local cmd
  for cmd in k3s kubectl crictl ctr; do
    upkg add -gp "$cmd" 'https://github.com/k3s-io/k3s/releases/download/v1.30.0%2Bk3s1/k3s' e4b85e74d7be314f39e033142973cc53619f4fbaff3639a420312f20dea12868
  done
  cp_tpl /etc/systemd/system/k3s@.target
  cp_tpl /etc/systemd/system/k3s@.service

  mkdir -p /etc/rancher/k3s/config.yaml.d
  cp_tpl /etc/rancher/k3s/agent.yaml
  cp_tpl /etc/rancher/k3s/server.yaml
  cp_tpl /etc/rancher/k3s/registry.yaml

  CILIUM_CLI_VERSION=$(wget -qO- https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  wget -qO>(tar xzC /usr/local/bin) "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH?}.tar.gz"
  cp_tpl --raw --chmod=0755 /usr/local/bin/install-cilium
  cp_tpl /etc/systemd/system/install-cilium.service
  systemctl enable install-cilium.service

  upkg add -gp kpt "https://github.com/kptdev/kpt/releases/download/v1.0.0-beta.50/kpt_linux_$ARCH"
  upkg add -gp kustomize -b kustomize "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_$ARCH.tar.gz"

  cp_tpl /etc/systemd/system/apply-all-manifests.service
  systemctl enable apply-all-manifests.service

  cp_tpl --raw --chmod=0755 /usr/local/bin/k3s-start
  cp_tpl /etc/systemd/system/k3s.service
  cp_tpl /etc/systemd/system/k3s.service
  systemctl enable k3s.service
  # sudo mkdir -p /var/lib/rancher/k3s/agent/images/
  # sudo curl -L -o /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst "https://github.com/k3s-io/k3s/releases/download/v1.29.1-rc2%2Bk3s1/k3s-airgap-images-amd64.tar.zst"
}
