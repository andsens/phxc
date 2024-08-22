#!/usr/bin/env bash

curl_boot_server() {
  curl --cacert /usr/local/share/ca-certificates/home-cluster-root.crt \
    -fL --no-progress-meter --connect-timeout 5 --retry 3 "$@"
}

boot_server_available() {
  boot_server=$(get_node_state boot-server) || return 1
  if [[ $(curl  --cacert /usr/local/share/ca-certificates/home-cluster-root.crt \
    -sw '%{http_code}' -o/dev/null "https://${boot_server}:8020/registry/health") = 200 ]]; then
    return 0
  else
    return 1
  fi
}
