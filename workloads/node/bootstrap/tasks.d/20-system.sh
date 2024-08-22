#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  tpm2-tools openssl xxd curl systemd-timesyncd # Remote attestation for cluster authentication
  less nano # TODO: debug
)

system() {
  cp /workspace/root_ca.crt /usr/local/share/ca-certificates/home-cluster-root.crt
  update-ca-certificates

  cp_tpl --raw \
    /etc/systemd/system/update-node-config.service \
    /etc/systemd/system/update-node-config.timer \
    /etc/systemd/system/update-boot.service \
    /etc/systemd/system/create-persistent-dir@.service \
    /etc/systemd/system/create-persistent-dir@.service \
    /etc/systemd/system/resource-ready@.service \
    /etc/systemd/system/resource-ready@.target \
    /etc/systemd/system.conf.d/variant.conf

  systemctl enable \
    systemd-timesyncd.service \
    update-node-config.service \
    update-node-config.timer \
    update-boot.service

  mkdir /var/lib/persistent
  if [[ $VARIANT = rpi* ]]; then
    ln -s ../persistent/home-cluster/systemd-credential.secret /var/lib/systemd/credential.secret
  fi
}
