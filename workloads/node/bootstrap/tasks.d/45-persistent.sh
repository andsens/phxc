#!/usr/bin/env bash

PACKAGES+=(
  libtss2-fapi1 libtss2-rc0 # Needed by systemd-cryptenroll for interacting with a TPM device
)

persistent() {
  mkdir -p /var/lib/rancher/k3s/agent/containerd
  cp_tpl --raw \
    /etc/systemd/system/setup-persistent.service \
    /etc/systemd/system/var-lib-rancher-k3s-agent-containerd.mount \
    /etc/systemd/system/var-lib-longhorn.mount
  systemctl enable \
    setup-persistent.service \
    var-lib-rancher-k3s-agent-containerd.mount \
    var-lib-longhorn.mount
}
