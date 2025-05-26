#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() {
  resource_phase_is phxc daemonset image-registry Running
  curl -sfk https://image-registry.phxc.svc.cluster.local:8020/health &>/dev/null
}
check_ready "$@"
