#!/bin/bash
set -Eeo pipefail

main() {
  : "${STEPPATH:?}"
  printf "ssh-host-jwt.sh: Initializing step-ca\n" >&2
  step ca bootstrap --ca-url "step-ca.smallstep.svc.cluster.local:9000" --fingerprint "$(step certificate fingerprint "$STEPPATH/root_ca.crt")"
  local host
  for host in $(kubectl get nodes -o=jsonpath='{.items[*].metadata.labels.kubernetes\.io/hostname}'); do
    printf "ssh-host-jwt.sh: Issuing token for %s\n" "$host" >&2
    step ca token \
      --provisioner=ssh-host --provisioner-password-file="$STEPPATH/ssh-host-provisioner-password/password" \
      --ssh --host "$host" > "/home/step/jwt/$host.jwt"
  done
}

main "$@"
