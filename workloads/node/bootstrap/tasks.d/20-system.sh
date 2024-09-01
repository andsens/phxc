#!/usr/bin/env bash

PACKAGES+=(
  systemd-cryptsetup # encrypted data
  tpm2-tools openssl xxd curl systemd-timesyncd # Remote attestation for cluster authentication
)

system() {
  cp /workspace/root_ca.crt /usr/local/share/ca-certificates/home-cluster-root.crt
  update-ca-certificates

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
