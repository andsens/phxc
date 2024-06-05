#!/usr/bin/env bash

persistent() {
  mkdir -p /var/lib/rancher/k3s/agent/containerd
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/persistent
  cp_tpl --raw /etc/systemd/system/mk-data-dirs.service
  systemctl enable mk-data-dirs.service
  cp_tpl --raw /etc/systemd/system/var-lib-rancher-k3s-agent-containerd.mount
  systemctl enable var-lib-rancher-k3s-agent-containerd.mount
}
