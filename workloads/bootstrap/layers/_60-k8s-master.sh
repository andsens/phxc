#!/usr/bin/env bash

PACKAGES+=(wget ca-certificates)

k8s_master() {
  # shellcheck disable=2054
  k3s_exec_flags=(
    --flannel-backend=none
    --egress-selector-mode=disabled
    --disable=coredns
    --disable=traefik
    --disable=metrics-server
    --disable=servicelb
    --disable=local-storage
    --disable-network-policy
    --disable-kube-proxy
    --disable-helm-controller
    "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=24"
    "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=112"
    "--cluster-cidr=${CLUSTER_CIDRS_PODIPV4},${CLUSTER_CIDRS_PODIPV6}"
    "--service-cidr=${CLUSTER_CIDRS_SVCIPV6},${CLUSTER_CIDRS_SVCIPV6}"
    "--tls-san=api.${CLUSTER_DOMAIN}"
  )

  INSTALL_K3S_SKIP_START=true \
  INSTALL_K3S_EXEC="${k3s_exec_flags[*]}" \
  bash <(wget -qO- https://get.k3s.io) || true # systemctl daemon-reload fails because dbus is not started. Ignore. It's the last action in the install script

  cp_tpl /etc/systemd/system/create-k3s-registry-config.service
  systemctl enable create-k3s-registry-config.service

  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  (
    set -e
    cd "/tmp"
    curl -sL --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH?}.tar.gz"{,.sha256sum}
    sha256sum --check "cilium-linux-$ARCH.tar.gz.sha256sum"
    tar xzvfC "cilium-linux-$ARCH.tar.gz" "/usr/local/bin"
    rm "cilium-linux-$ARCH.tar.gz"{,.sha256sum}
  )
  cp_tpl /etc/systemd/system/install-cilium.service
  systemctl enable install-cilium.service

  wget -qO/usr/local/bin/kpt "https://github.com/kptdev/kpt/releases/download/v1.0.0-beta.49/kpt_linux_$ARCH"
  chmod +x /usr/local/bin/kpt
  wget -qO- "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_$ARCH.tar.gz" | tar xzC /usr/local/bin/ kustomize
  chmod +x /usr/local/bin/kustomize

  cp_tpl /etc/systemd/system/apply-all-manifests.service
  systemctl enable apply-all-manifests.service
}
