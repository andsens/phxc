#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() { kubectl get clusterissuer selfsigned -ojsonpath='{.status.conditions}' | status_is_ready; }
check_ready "$@"
