#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/workloads/auth/lib/auth.sh"
  # shellcheck disable=SC2016
  yq \
    --arg crt "$(cat "$(get_client_crt_path home-cluster-kube-api)")" \
    --arg key "$(cat "$(get_client_key_path home-cluster-kube-api)")" \
    '.status.clientCertificateData=$crt | .status.clientKeyData=$key' \
    <<<'{"apiVersion": "client.authentication.k8s.io/v1beta1","kind": "ExecCredential"}'
}

main "$@"
