#!/usr/bin/env bash
# shellcheck source-path=../../
set -eo pipefail; shopt -s inherit_errexit
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done
source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
source "$PKGROOT/manifests/lib/common.sh"

MANIFEST_ROOT=$(dirname "${BASH_SOURCE[0]}")
kustomize build --enable-alpha-plugins "$MANIFEST_ROOT" | kpt live apply --context "$CLUSTER_CONTEXT" - "$@"
