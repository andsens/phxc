#!/usr/bin/env bash
# shellcheck source-path=../../
set -Eeo pipefail
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done
source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

MANIFEST_ROOT=$(dirname "${BASH_SOURCE[0]}")
kustomize build "$MANIFEST_ROOT" | kpt live apply --context k3s - "$@"
