#!/usr/bin/env bash

PACKAGES+=(
  tpm2-tools openssl xxd curl systemd-timesyncd # Remote attestation for cluster authentication
)

system() {
  cp /workspace/root_ca.crt /usr/local/share/ca-certificates/home-cluster-root.crt
  update-ca-certificates

  cp_tpl --raw \
    /etc/systemd/system/mount-boot.service \
    /etc/systemd/system/monitor-node-config.service \
    /etc/systemd/system/cluster-auth.service \
    /etc/systemd/system/collect-node-state.service \
    /etc/systemd/system/report-node-state.path \
    /etc/systemd/system/report-node-state.service \
    /etc/systemd/system/update-boot.service \
    /etc/systemd/system/setup-data.service \
    /etc/systemd/system/create-persistent-dir@.service \
    /etc/systemd/system/create-persistent-dir@.service \
    /etc/systemd/system/resource-ready@.service \
    /etc/systemd/system/resource-ready@.target

  systemctl enable \
    systemd-timesyncd.service \
    mount-boot.service \
    monitor-node-config.service \
    collect-node-state.service \
    report-node-state.path \
    report-node-state.service \
    update-boot.service \
    cluster-auth.service \
    setup-data.service

  mkdir /var/lib/persistent
}
