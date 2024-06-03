#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")

main() {
  PATH=$(path_prepend "$PKGROOT/.upkg/.bin")
  local items
  items=$(kubectl create configmap settings.yaml "$PKGROOT/settings.yaml")
  # shellcheck disable=SC2016
  yq --arg items "$items" '.items+=[$items]' <<<'kind: ResourceList
items: []
'
}

main "$@"
