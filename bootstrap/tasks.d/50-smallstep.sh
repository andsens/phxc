#!/usr/bin/env bash

smallstep() {
  if [[ -e /workspace/secureboot/ca.crt ]]; then
    cp /workspace/secureboot/ca.crt /usr/local/share/ca-certificates/phxc-root.crt
    openssl x509 -in /usr/local/share/ca-certificates/phxc-root.crt -outform der -out /usr/local/share/phxc/phxc-root.der
  fi
}
