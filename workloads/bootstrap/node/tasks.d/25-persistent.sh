#!/usr/bin/env bash

persistent() {
  mkdir -p /var/lib/rancher/k3s/agent/containerd
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/persistent
  cp_tpl --raw \
    /etc/systemd/system/mk-data-dirs.service \
    /etc/systemd/system/var-lib-rancher-k3s-agent-containerd.mount \
    /etc/systemd/system/var-lib-longhorn.mount
  systemctl enable \
    mk-data-dirs.service \
    var-lib-rancher-k3s-agent-containerd.mount \
    var-lib-longhorn.mount
}
