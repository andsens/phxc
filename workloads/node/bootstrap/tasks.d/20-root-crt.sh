#!/usr/bin/env bash

root_crt() {
  cp /workspace/root_ca.crt /usr/local/share/ca-certificates/home-cluster-root.crt
  update-ca-certificates
}
