#!/usr/bin/env bash

cachedev() {
  mkdir -p /var/lib/rancher/k3s/agent/containerd
  cp_tpl --raw --chmod=0755 /etc/initramfs-tools/scripts/init-bottom/cachedev
  cp_tpl --raw --chmod=0755 /etc/systemd/system/mk-cache-dirs.service
  cp_tpl --raw --chmod=0755 /etc/systemd/system/var-lib-rancher-k3s-agent-containerd.mount
}
