#!/usr/bin/env bash
# shellcheck source-path=../../
set -eo pipefail; shopt -s inherit_errexit
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done
source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
source "$PKGROOT/manifests/lib/common.sh"
source "$PKGROOT/manifests/lib/generate-replacement.sh"
source "$PKGROOT/vars.sh"

generate_replacement nas-replacement \
  NFS_CLUSTER_SERVER_IP \
  NFS_CLUSTER_SERVER_IP_CIDR \
  NFS_CLUSTER_SHARE \
  NFS_CLUSTER_SUBDIR
