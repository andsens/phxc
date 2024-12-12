#!/usr/bin/env bash

PACKAGES+=(openssh-server)

sshd() {
  debconf-set-selections <<<"openssh-server  openssh-server/password-authentication  boolean false"
  rm /etc/ssh/ssh_host_*
}
