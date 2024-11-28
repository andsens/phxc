#!/usr/bin/env bash

PACKAGES+=(openssh-server)

sshd() {
  local filepath systemd_units=(
    60-ssh/download-ssh-user-ca-keys.service
    60-ssh/generate-ssh-host-keys.service
    60-ssh/sign-ssh-host-keys.service
    60-ssh/sign-ssh-host-keys.timer
  )
  for filepath in "${systemd_units[@]}"; do
    cp_tpl --raw "_systemd_units/$filepath" -d "/etc/systemd/system/$(basename "$filepath")"
  done
  debconf-set-selections <<<"openssh-server  openssh-server/password-authentication  boolean false"
  rm /etc/ssh/ssh_host_*

  export CLUSTER_SMALLSTEP_LB_FIXEDIPV4 SMALLSTEP_ROOT_CA_FINGERPRINT
  SMALLSTEP_ROOT_CA_FINGERPRINT=$(step certificate fingerprint /usr/local/share/ca-certificates/phoenix-cluster-root.crt)
  cp_tpl --chmod 0600 --var CLUSTER_SMALLSTEP_LB_FIXEDIPV4 --var SMALLSTEP_ROOT_CA_FINGERPRINT /root/.step/config/defaults.json

  cp_tpl --raw \
    /etc/ssh/sshd_config.d/10-no-root-login.conf \
    /etc/ssh/sshd_config.d/20-host-key-certs.conf \
    /etc/ssh/sshd_config.d/30-user-ca-keys.conf \
    /etc/ssh/sshd_config.d/50-tmux.conf
  systemctl enable \
    generate-ssh-host-keys.service \
    download-ssh-user-ca-keys.service \
    sign-ssh-host-keys.service \
    sign-ssh-host-keys.timer
}
