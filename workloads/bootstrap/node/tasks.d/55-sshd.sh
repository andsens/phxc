#!/usr/bin/env bash

PACKAGES+=(openssh-server)

sshd() {
  debconf-set-selections <<<"openssh-server  openssh-server/password-authentication  boolean false"
  rm /etc/ssh/ssh_host_*

  cp_tpl --raw \
    /etc/ssh/sshd_config.d/10-no-root-login.conf \
    /etc/ssh/sshd_config.d/20-host-key-certs.conf \
    /etc/ssh/sshd_config.d/30-user-ca-keys.conf \
    /etc/ssh/sshd_config.d/50-tmux.conf \
    /etc/systemd/system/generate-ssh-host-keys.service \
    /etc/systemd/system/download-ssh-user-ca-keys.service \
    /etc/systemd/system/sign-ssh-host-keys.service \
    /etc/systemd/system/sign-ssh-host-keys.timer
  systemctl enable \
    generate-ssh-host-keys.service \
    download-ssh-user-ca-keys.service \
    sign-ssh-host-keys.service \
    sign-ssh-host-keys.timer
}
