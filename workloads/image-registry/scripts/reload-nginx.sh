#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  "$@"
  until [[ -f /var/cache/nginx/pid ]]; do sleep .1; done
  trap 'kill $(cat /var/cache/nginx/pid) $SLEEP_PID; exit 0' TERM INT EXIT

  local modtime old_modtime
  old_modtime=$(stat -c%Y "$(realpath /etc/nginx/nginx-conf/nginx.conf)" "$(realpath /etc/nginx/tls/tls.crt)")
  while true; do
    modtime=$(stat -c%Y "$(realpath /etc/nginx/nginx-conf/nginx.conf)" "$(realpath /etc/nginx/tls/tls.crt)")
    if [[ $modtime != "$old_modtime" ]]; then
      printf "Config or certificate changed, reloading nginx\n" >&2
      kill -HUP "$(cat /var/cache/nginx/pid)"
      old_modtime=$modtime
    fi
    sleep 5 & SLEEP_PID=$!
    wait || break
  done
}

main "$@"
