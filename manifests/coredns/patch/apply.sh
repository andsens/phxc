#!/usr/bin/env bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

patch_data=$(kustomize build --enable-alpha-plugins --enable-exec "$PKGROOT/manifests/coredns/patch")
kubectl patch -n kube-system deployment coredns --type strategic --patch "$patch_data"
