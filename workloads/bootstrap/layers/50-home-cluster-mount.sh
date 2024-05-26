#!/usr/bin/env bash

PACKAGES+=(nfs-common)

home_cluster_mount() {
  cp_tpl /etc/systemd/system/var-lib-home\\x2dcluster.mount
  systemctl enable var-lib-home\\x2dcluster.mount
}
