#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() {
  deployment_ready cert-manager cert-manager
  deployment_ready cert-manager cert-manager-cainjector
  deployment_ready cert-manager cert-manager-webhook
  crd_installed certificates.cert-manager.io
}
check_ready "$@"
