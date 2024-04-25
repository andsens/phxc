#!/bin/bash
set -Eeo pipefail

main() {
  : "${STEPPATH:?}" "${STEP_CA_DOMAIN:?}"
  apk add --update --no-cache jq
  jq --arg domain "$STEP_CA_DOMAIN" '.dnsNames+=[$domain]' "$STEPPATH/config-ro/ca.json" > "$STEPPATH/config/ca.json"
  printf "setup-config.sh: Adding step-issuer to ca.json\n" >&2
  step ca provisioner add step-issuer --type JWK \
    --public-key="$STEPPATH/certs/issuer-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/issuer-provisioner/priv.json" \
    --password-file="$STEPPATH/issuer-provisioner-password/password"
}

main "$@"
