#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

# Authenticate by verifying possession a certificate pubkey transmitted through
# the JWS X5C header. Then check the certificate agaings the kube client-ca.
main() {
  local input claimed_username jws username groups
  # The password is the JWS
  input=$(cat)
  IFS=' ' read -r -d $'\n' claimed_username jws <<<"$input"
  # Extract & decode the attached x5c certificate
  json=$(step crypto jws inspect --insecure --json <<<"$jws")
  cert=$(printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----' "$(jq -r '.header.x5c[0]' <<<"$json")")
  # Verify possession by checking the JWS signature against the attached cert
  step crypto jws verify --key <(printf "%s" "$cert") <<<"$jws"
  # Check if the attached cert is signed by the CA
  step certificate verify <(printf "%s" "$cert") --roots /config/certs/kube_apiserver_client_ca.crt
  # Extract the username
  username=$(step certificate inspect <(printf "%s" "$cert") --format json | jq -r '.subject.common_name[0]')
  username=${username//:/'/'} # No way to include colon in basic auth username
  groups=$(step certificate inspect <(printf "%s" "$cert") --format json | jq '.subject.organization')
  # Check the username against the claimed login username, and attach groups
  if [[ $username = "$claimed_username" ]]; then
    jq --argjson groups "$groups" '{"labels": {"groups": $groups}}' <<<'{}'
    return 0
  else
    return 2
  fi
}

main "$@"
