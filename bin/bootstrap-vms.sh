#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"

  DOC="bootstrap-vms - Bootstrap multiple VMs
Usage:
  bootstrap-vms [HOSTNAMES...]
"
# docopt parser below, refresh this parser with `docopt.sh bootstrap-vms.sh`
# shellcheck disable=2016,1090,1091,2034,2154
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:76}; usage=${DOC:39:37}; digest=d4a08; shorts=(); longs=()
argcounts=(); node_0(){ value HOSTNAMES a true; }; node_1(){ oneormore 0; }
node_2(){ optional 1; }; node_3(){ required 2; }; node_4(){ required 3; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:39:37}" >&2; exit 1; }'; unset var_HOSTNAMES; parse 4 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}HOSTNAMES"
if declare -p var_HOSTNAMES >/dev/null 2>&1; then
eval "${prefix}"'HOSTNAMES=("${var_HOSTNAMES[@]}")'; else
eval "${prefix}"'HOSTNAMES=()'; fi; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}HOSTNAMES"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' bootstrap-vms.sh`
  eval "$(docopt "$@")"
  source "$PKGROOT/vars.sh"
  confirm_machine_id bootstrapper

  if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
    if [[ ! -e "$PKGROOT/bootstrap-vms.args.sh" ]]; then
      info "$PKGROOT/bootstrap-vms.args.sh does not exist (and no hostnames provided on commandline), exiting"
      return 0
    else
      # shellcheck disable=1091
      source "$PKGROOT/bootstrap-vms.args.sh"
      # shellcheck disable=2064
      trap "rm \"$PKGROOT/bootstrap-vms.args.sh\"" EXIT
    fi
  fi

  local hostname ret=0
  for hostname in "${HOSTNAMES[@]}"; do
    info "Bootstrapping %s" "$hostname"
    if "$PKGROOT/bin/bootstrap.sh" --cachepath="/var/lib/persistent/cache" "$hostname"; then
      info "Successfully bootstrapped %s" "$hostname"
      mv "$PKGROOT/images/$hostname.raw" "$PKGROOT/images/$hostname.latest.raw"
    else
      error "Failed to bootstrap %s" "$hostname"
      rm -f "$PKGROOT/images/$hostname.raw"
      ret=1
    fi
  done
  return $ret
}

main "$@"
