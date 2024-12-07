#!/usr/bin/env bash

PACKAGES+=(openssh-server)

sshd() {
  install_sd_unit ssh/download-ssh-user-ca-keys.service
  install_sd_unit ssh/generate-ssh-host-keys.service
  install_sd_unit ssh/sign-ssh-host-keys.service
  install_sd_unit ssh/sign-ssh-host-keys.timer
  debconf-set-selections <<<"openssh-server  openssh-server/password-authentication  boolean false"
  rm /etc/ssh/ssh_host_*

  cp_tpl \
    /etc/ssh/sshd_config.d/10-no-root-login.conf \
    /etc/ssh/sshd_config.d/30-user-ca-keys.conf \
    /etc/ssh/sshd_config.d/50-tmux.conf
  systemctl enable \
    generate-ssh-host-keys.service \
    download-ssh-user-ca-keys.service \
    sign-ssh-host-keys.service \
    sign-ssh-host-keys.timer
}
