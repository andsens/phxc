#!/usr/bin/env bash

smallstep() {
  mkdir -p /root/.step/config
  install_sd_unit smallstep/install-smallstep.service
  install_sd_unit smallstep/bootstrap-smallstep.service
  install_sd_unit smallstep/trust-smallstep-root.service
}
