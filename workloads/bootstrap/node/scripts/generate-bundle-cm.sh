#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")

main() {
  source "$PKGROOT/.upkg/path-tools/path-tools.sh"
  PATH=$(path_prepend "$PKGROOT/.upkg/.bin")
  local bundle item
  bundle=$(mktemp --suffix .tar.gz)
  # shellcheck disable=SC2064
  trap "rm \"$bundle\"" EXIT
  "$PKGROOT/workloads/bootstrap/containers/bin/bundle.sh" "$bundle"
  item=$(kubectl create --dry-run=client -o yaml configmap bundle --from-file "home-cluster.tar.gz=$bundle")
  # shellcheck disable=SC2016
  yq -y --indentless --argjson item "$(yq . <<<"$item")" '.items+=[$item]' <<<'kind: ResourceList
items: []'
}

main "$@"
