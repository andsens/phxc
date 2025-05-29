#!/usr/bin/env bash

debug_pre_copy() {
  if ! $DEBUG; then
    FILES_EXCLUDE+=(
      /etc/systemd/system.conf.d/debug-logging.conf
    )
  fi
}

debug() {
  if $DEBUG; then
    printf "
!!! ATTENTION !!!
The Phoenix Cluster image has been bootstrapped with the debug flag enabled.
This means:
* root account login is enabled (through SSH & the console)
* initramfs allows shell access
* SSH password login is enabled
Your cluster is not secure when using debug mode.
" >>/etc/motd
  fi
}
