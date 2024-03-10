#!/usr/bin/env bash
# shellcheck source-path=../../
set -eo pipefail; shopt -s inherit_errexit
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done
source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

MANIFEST_ROOT=$(dirname "${BASH_SOURCE[0]}")
# shellcheck disable=2034,2269
(
  source "$PKGROOT/vars.sh"
  source "$PKGROOT/manifests/lib/generate-replacement.sh"
  NFS_SERVER_IP=$NFS_CLUSTER_SERVER_IP
  NFS_SHARE=$NFS_CLUSTER_SHARE
  NFS_SUBDIR=$NFS_CLUSTER_SUBDIR
  generate_replacement nas-replacement NFS_SERVER_IP NFS_SHARE NFS_SUBDIR
) >"$MANIFEST_ROOT/nas-replacement.yaml"
kustomize build "$MANIFEST_ROOT" | kpt live apply --context k3s - "$@"
