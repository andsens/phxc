#!/usr/bin/env bash
# shellcheck source-path=..
# shellcheck disable=2064

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"

  DOC="inject-dc-secrets.sh - Inject configuration secrets for FreeIPA into a raw image
Usage:
  inject-dc-config SECRETSPATH IMAGEPATH
"
# docopt parser below, refresh this parser with `docopt.sh inject-dc-secrets.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:128}; usage=${DOC:81:47}; digest=499e1; shorts=(); longs=()
argcounts=(); node_0(){ value SECRETSPATH a; }; node_1(){ value IMAGEPATH a; }
node_2(){ required 0 1; }; node_3(){ required 2; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:81:47}" >&2; exit 1
}'; unset var_SECRETSPATH var_IMAGEPATH; parse 3 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}SECRETSPATH" \
"${prefix}IMAGEPATH"; eval "${prefix}"'SECRETSPATH=${var_SECRETSPATH:-}'
eval "${prefix}"'IMAGEPATH=${var_IMAGEPATH:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}SECRETSPATH" "${prefix}IMAGEPATH"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' inject-dc-secrets.sh`
  eval "$(docopt "$@")"

  if [[ $UID != 0 ]]; then
    fatal "Run with sudo"
  fi
  local mountpath
  mountpath=$(mktemp -d)
  trap "rm -rf \"$mountpath\"" EXIT ERR
  (
    devpath=$(losetup --show --find --partscan "$IMAGEPATH")
    trap "losetup --detach \"$devpath\"" EXIT ERR
    (
      mount "${devpath}p2" "$mountpath"
      trap "umount \"$mountpath\"" EXIT ERR
      printf -- "--ds-password=%q\n--admin-password=%q\n" \
        "$(jq -r '.["ds-password"]' "$SECRETSPATH")" \
        "$(jq -r '.["admin-password"]' "$SECRETSPATH")" \
        >> "$mountpath/etc/freeipa/ipa-server-install-options"
    )
  )
}

main "$@"
