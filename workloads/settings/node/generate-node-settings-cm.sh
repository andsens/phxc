#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  local mac node cm='kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: node-settings
  data:
'
  # shellcheck disable=SC2016
  for node in $(yq -c '.nodes[]' "$PKGROOT/settings.yaml"); do
    ! mac=$(yq -re '.mac' <<<"$node")|| \
      cm=$(yq -y --indentless --arg mac "$mac" --arg node "$node" '.items[0].data["\($mac).json"]=$node' <<<"$cm")
  done
  printf "%s\n" "$cm"
}

main "$@"
