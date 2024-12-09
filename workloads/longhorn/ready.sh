#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() {
  deployment_ready longhorn-system csi-attacher
  deployment_ready longhorn-system csi-provisioner
  deployment_ready longhorn-system csi-resizer
  deployment_ready longhorn-system csi-snapshotter
  deployment_ready longhorn-system longhorn-driver-deployer
}
check_ready "$@"
