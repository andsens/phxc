#!/bin/bash
set -Eeo pipefail

main() {
  : "${STEPPATH:?}" "${STEP_CA_DOMAIN:?}"
  apk add --update --no-cache jq
  jq --arg domain "$STEP_CA_DOMAIN" '.dnsNames+=[$domain]' "$STEPPATH/config-ro/ca.json" > "$STEPPATH/config/ca.json"
  printf "setup-config.sh: Adding step-issuer to ca.json\n" >&2
  step ca provisioner add step-issuer --type JWK \
    --public-key="$STEPPATH/certs/step-issuer-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/step-issuer-provisioner/priv.json" \
    --password-file="$STEPPATH/step-issuer-provisioner-password/password"
  step ca provisioner add ssh-host --type JWK \
    --public-key="$STEPPATH/certs/ssh-host-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/ssh-host-provisioner/priv.json" \
    --password-file="$STEPPATH/ssh-host-provisioner-password/password"
}

main "$@"
