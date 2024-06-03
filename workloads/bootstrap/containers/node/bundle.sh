#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")

main() {
  # shellcheck disable=SC1091
  source "$PKGROOT/.upkg/path-tools/path-tools.sh"
  local dest=${1:?} version_flag
  version_flag=$(jq -r '.version // empty' "$PKGROOT/upkg.json")
  [[ -z $version_flag ]] || version_flag=-V$version_flag
  PATH=$(path_prepend "$PKGROOT/.upkg/.bin")
  # shellcheck disable=SC2086
  upkg bundle -d"$dest" $version_flag \
    bin workloads README.md settings.template.yaml settings.yaml
}

main "$@"
