#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

SETTINGS=/var/lib/home-cluster/settings.yaml
MANIFESTS=/pxe-manifests

main() {
  source "$PKGROOT/lib/common.sh"

  generate_pxe_manifests
  monitor_settings &

  mkdir -p /var/lib/nginx/tmp /var/lib/nginx/run /var/lib/nginx/logs
  exec nginx
}

monitor_settings() {
  local current_settings
  current_settings=$(cat "$SETTINGS")
  export TMPDIR=/var/lib/nginx
  while true; do
    if ! diff -q <(printf "%s\n" "$current_settings") "$SETTINGS"; then
      info "%s changed" "$SETTINGS"
      generate_pxe_manifests
    fi
    current_settings=$(cat "$SETTINGS")
    sleep 10
  done
}

generate_pxe_manifests() {
  local mac node
  info "Generating manifests"
  rm -f "$MANIFESTS"/*.json
  # shellcheck disable=SC2016
  for node in $(yq -r '.nodes | keys[]' "$SETTINGS"); do
    if mac=$(yq -re --arg node "$node" '.nodes[$node].mac' "$SETTINGS"); then
      yq --arg node "$node" '{
        hostname: .nodes[$node].hostname,
        networks: .nodes[$node].networks
      }' "$SETTINGS" >"$MANIFESTS/${mac,,}.json"
    fi
  done
}

main "$@"

# $ cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address
