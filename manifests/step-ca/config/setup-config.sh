#!/bin/bash
set -eo pipefail; shopt -s inherit_errexit

main() {
  : "${STEPPATH:?}"
  cp "$STEPPATH/config-ro/ca.json" "$STEPPATH/config/ca.json"
  printf "setup-config.sh: Adding step-issuer to ca.json\n" >&2
  step ca provisioner add step-issuer --type JWK \
    --public-key="$STEPPATH/certs/issuer-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/issuer-provisioner/priv.json" \
    --password-file="$STEPPATH/issuer-provisioner-password/password"
}

main "$@"
