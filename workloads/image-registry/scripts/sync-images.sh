#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
source "$PKGROOT/.upkg/records.sh/records.sh"

main() {
  trap 'kill $SLEEP_PID; exit 0' INT TERM
  while true; do
    sync "$@"
    sleep 3600 & $SLEEP_PID
    wait
  done
}

sync() {
  info "Synchronizing images"
  local variants=("$@") variant lock_pid registries=() registry epoch file
  readarray -d $'\n' -t registries < <(dig +search +short image-registry-headless)
  for variant in "${variants[@]}"; do
    wait_for_unlock "/var/lib/phxc/images/$variant.tmp"
    rm -rf "/var/lib/phxc/images/$variant.tmp"
    keep_locked "/var/lib/phxc/images/$variant.tmp" & lock_pid=$!
    local latest='' sync_from=''
    latest=$(jq -r '.buildDate // empty' "/var/lib/phxc/images/$variant/meta.json" 2>/dev/null || true)
    for registry in "${registries[@]}"; do
      [[ $registry != "$POD_IP" ]] || continue
      if epoch=$(date -uD "%Y-%m-%dT%H:%M:%S+00:00" -d "$(curl_imgreg "$registry" "$variant/meta.json" | jq -re .buildDate)" +%s); then
        if [[ -z $latest || $epoch -gt $latest ]]; then
          latest=$epoch
          sync_from=$registry
        fi
      fi
    done
    if [[ -n $sync_from ]]; then
      info "Found newer image for variant %s on %s, fetching now" "$variant" "$registry"
      for file in $(curl_imgreg "$registry" "$variant" | jq -r '.[] | .name'); do
        curl_imgreg "$registry" "$variant/$file" -o"/var/lib/phxc/images/$variant.tmp/$file"
      done
      rm -rf "/var/lib/phxc/images/$variant.old"
      [[ ! -e "/var/lib/phxc/images/$variant" ]] || mv "/var/lib/phxc/images/$variant" "/var/lib/phxc/images/$variant.old"
      mv "/var/lib/phxc/images/$variant.tmp" "/var/lib/phxc/images/$variant"
    elif [[ -f "/var/lib/phxc/images/$variant/meta.json" ]]; then
      info "Newest image for variant %s already present on this host" "$variant"
    else
      info "No image for variant %s found" "$variant"
    fi
    rm -rf "/var/lib/phxc/images/$variant.tmp"
    kill $lock_pid
  done
}

wait_for_unlock() {
  local lock_dir=${1%'/'} locked_until locked_for
  while locked_until=$(cat "$lock_dir/lock" 2>/dev/null); do
    locked_for=$(( locked_until - $(date +%s) ))
    [[ $locked_for -gt 0 ]] || break
    info "%s is locked for %d seconds, waiting for lock release" "$lock_dir" "$locked_for"
    sleep $locked_for
  done
}

keep_locked() {
  local lock_dir=${1%'/'}
  mkdir -p "$lock_dir"
  while true; do
    printf "%d" "$(( $(date +%s) + 60 ))" >"$lock_dir/lock"
    sleep 50
  done
}

curl_imgreg() {
  local ip=$1 path=${2#'/'}
  shift; shift
  curl --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -fL --no-progress-meter \
    --connect-to "image-registry.phxc.svc.cluster.local:8020:$ip:8020" \
    "https://image-registry.phxc.svc.cluster.local:8020/$path" "$@"
}

main "$@"
