#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")

main() {
  local dest=${1:?} version_flag
  version_flag=$(jq -r '.version // empty' "$PKGROOT/upkg.json")
  [[ -z $version_flag ]] || version_flag=-V$version_flag
  local bundle_files=(README.md)
  if [[ -e $PKGROOT/.git ]]; then
    local filepath
    while read -r -d $'\0' filepath; do
      [[ ! -e $PKGROOT/$filepath && ! -L $PKGROOT/$filepath ]] || bundle_files+=("$filepath")
    done < <(cd "$PKGROOT"; git -C "$PKGROOT" ls-files -zco --exclude-standard bin bootstrap lib workloads)
  else
    bundle_files+=(bin bootstrap lib workloads)
  fi
  # shellcheck disable=SC2086
  (
    cd "$PKGROOT"
    upkg bundle -qd"$dest" $version_flag "${bundle_files[@]}" >/dev/null
  )
  local bundle_size
  bundle_size=$(stat -c %s "$dest")
  (( bundle_size < 1024 * 256 )) || printf "bundle: Bundle size is %d (>256KiB)\n" "$bundle_size" >&2
}

main "$@"
