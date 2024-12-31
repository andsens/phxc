#!/usr/bin/env bash

secureboot() {
  if [[ -e /workspace/secureboot/tls.crt ]]; then
    openssl x509 -in /workspace/secureboot/tls.crt -outform der -out /usr/local/share/ca-certificates/secureboot.der
  fi
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system/enroll-mok.service
  else
    rm /etc/systemd/system/enroll-rpi-sb-cert.service
  fi
}
