#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")

main() {
  local settings
  settings=$(cat "$PKGROOT/settings.yaml")
  # shellcheck disable=SC2016
  yq --arg settings "$settings" '.items[0].data["settings.yaml"]=$settings' <<<'kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: settings-yaml
  data:
'
}

main "$@"
