#!/usr/bin/env bash

sshd_pre_install() {
  PACKAGES+=(openssh-client openssh-server)
  if ! $DEBUG; then
    DEBCONF_SELECTIONS+=(
      "openssh-server  openssh-server/permit-root-login boolean false"
      "openssh-server  openssh-server/password-authentication  boolean false"
    )
  fi
}
