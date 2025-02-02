#!/usr/bin/env bash

PACKAGES+=(openssh-client openssh-server)

sshd() {
  debconf-set-selections <<<"openssh-server  openssh-server/password-authentication  boolean false"
}
