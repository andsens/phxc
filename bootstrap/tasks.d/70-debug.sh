#!/usr/bin/env bash

debug() {
  if $DEBUG; then
    ! $DEBUG || printf "
!!! ATTENTION !!!
The Phoenix Cluster image has been bootstrapped with the debug flag enabled.
This means the root account is unlocked and shell access in initramfs is
enabled. Your cluster is not secure when using debug mode.
" >>/etc/motd
  else
    $DEBUG || rm /etc/systemd/system.conf.d/debug.conf
  fi
}
