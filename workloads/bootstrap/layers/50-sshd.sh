#!/usr/bin/env bash

PACKAGES+=(openssh-server wget ca-certificates)

sshd() {
  debconf-set-selections <<<"openssh-server  openssh-server/password-authentication  boolean false"

  cp_tpl /etc/ssh/sshd_config.d/10-no-root-login.conf
  cp_tpl /etc/ssh/sshd_config.d/50-tmux.conf

  rm /etc/ssh/ssh_host_*
  cp_tpl /etc/systemd/system/generate-ssh-host-keys.service
  systemctl enable generate-ssh-host-keys.service

  wget -qO- "https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.26.0/step_linux_0.26.0_${MACHINE_ARCH:?}.tar.gz" | \
    tar xzC /usr/local/bin --strip-components 2 step_0.26.0/bin/step
  chmod +x /usr/local/bin/step

  for unit in download-ssh-user-ca-keys.service sign-ssh-host-keys.service sign-ssh-host-keys.timer; do
    cp_tpl /etc/systemd/system/$unit
    systemctl enable $unit
  done

  cp_tpl /etc/ssh/sshd_config.d/20-host-key-certs.conf
  cp_tpl /etc/ssh/sshd_config.d/30-user-ca-keys.conf
}
