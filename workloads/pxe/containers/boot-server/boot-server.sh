#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
# shellcheck disable=SC1091
source "$PKGROOT/.upkg/records.sh/records.sh"

SETTINGS=/var/lib/home-cluster/settings.yaml
MANIFESTS=/pxe-manifests

main() {
  generate-node-settings.sh "$SETTINGS" "$MANIFESTS"
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
      generate-node-settings.sh "$SETTINGS" "$MANIFESTS"
    fi
    current_settings=$(cat "$SETTINGS")
    sleep 10
  done
}

main "$@"
