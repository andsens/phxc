#!/usr/bin/env bash

debug() {
  $DEBUG || rm /etc/systemd/system.conf.d/debug.conf
}
