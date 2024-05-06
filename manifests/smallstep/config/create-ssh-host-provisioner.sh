#!/bin/bash
set -Eeo pipefail; shopt -s inherit_errexit

: "${STEPPATH:?}" "${NAMESPACE:?}"
SSH_HOST_DIR=$STEPPATH/certs/ssh-host-provisioner

main() {
  info "Setting up SSH host provisioner"

  mkdir "$SSH_HOST_DIR"
  if ! kubectl get -n "$NAMESPACE" secret ssh-host-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$SSH_HOST_DIR/pub.json"; then
    info "ssh-host provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$STEPPATH/ssh-host-provisioner-password/password" \
      --use sig \
      "$SSH_HOST_DIR/pub.json" "$SSH_HOST_DIR/priv.json"
    kubectl create -n "$NAMESPACE" secret generic ssh-host-provisioner \
      --from-file="$SSH_HOST_DIR/pub.json" \
      --from-file="$SSH_HOST_DIR/priv.json"
  else
    info "ssh-host provisioner validation succeeded"
  fi
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "%s: $tpl\n" "$(basename "$0")" "$@" >&2
}

main "$@"
