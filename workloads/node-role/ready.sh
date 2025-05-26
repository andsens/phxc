#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() {
  # If we can get the namespace this means the permissions have been assigned
  resource_phase_is namespace kube-system Active
}
check_ready "$@"
