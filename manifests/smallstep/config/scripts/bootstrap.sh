#!/bin/bash
set -Eeo pipefail; shopt -s inherit_errexit

PKGROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")")

main() {
  "$PKGROOT/create-cas.sh"
  "$PKGROOT/create-step-issuer.sh"
  "$PKGROOT/create-ssh-host-provisioner.sh"
  "$PKGROOT/create-kube-admin-config.sh"
}

main "$@"
