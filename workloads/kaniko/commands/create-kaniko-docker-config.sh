#!/bin/bash
# shellcheck source-path=../../..
# shellcheck disable=SC2016
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
source "$PKGROOT/lib/common.sh"

main() {
  local kaniko_username kaniko_password docker_config
  kaniko_username=$(kubectl get -n docker-registry secret kaniko-credentials -o jsonpath='{.data.username}' | base64 -d)
  kaniko_password=$(kubectl get -n docker-registry secret kaniko-credentials -o jsonpath='{.data.password}' | base64 -d)
  docker_config=$(printf '{
  "auths": {
    "distribution.docker-registry.svc.cluster.local": {
      "auth": "%s"
    }
  }
}
' "$(printf "%s:%s" "$kaniko_username" "$kaniko_password" | base64 -w0)")
  if [[ $(kubectl get -n "$NAMESPACE" secret kaniko-docker-config -o jsonpath='{.data.config\.json}' | base64 -d) != "$docker_config" ]]; then
    info "kaniko docker config secret validation failed, (re-)creating now"
    kubectl delete -n "$NAMESPACE" secret kaniko-docker-config 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret generic kaniko-docker-config --from-literal=config.json="$docker_config"
  else
    info "kaniko docker config secret validation succeeded"
  fi
}

main "$@"
