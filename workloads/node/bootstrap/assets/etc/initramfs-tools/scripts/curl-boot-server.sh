#!/usr/bin/env bash

curl_boot_server() {
  curl --cacert /usr/local/share/ca-certificates/home-cluster-root.crt \
    -fL --no-progress-meter --connect-timeout 5 --retry 3 "$@"
}
