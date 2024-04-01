#!/usr/bin/env bash
# shellcheck source-path=..
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"

  DOC="update-home-cluster-src - Clone/update the home-cluster source code
Usage:
  update-home-cluster-src [options] [REF]

Options:
  --deploy-key=PATH  Path to a deploy key when using a private repo
"
# docopt parser below, refresh this parser with `docopt.sh update-home-cluster-src.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:194}; usage=${DOC:68:48}; digest=ce726; shorts=('')
longs=(--deploy-key); argcounts=(1); node_0(){ value __deploy_key 0; }
node_1(){ value REF a; }; node_2(){ optional 0; }; node_3(){ optional 2; }
node_4(){ optional 1; }; node_5(){ required 3 4; }; node_6(){ required 5; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:68:48}" >&2; exit 1; }'; unset var___deploy_key var_REF
parse 6 "$@"; local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}__deploy_key" \
"${prefix}REF"; eval "${prefix}"'__deploy_key=${var___deploy_key:-}'
eval "${prefix}"'REF=${var_REF:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__deploy_key" "${prefix}REF"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' update-home-cluster-src.sh`
  eval "$(docopt "$@")"
  source "$PKGROOT/vars.sh"
  confirm_machine_id truenas

  if [[ -n $__deploy_key ]]; then
    eval "$(ssh-agent)" >&2
    ssh-add -q "$__deploy_key"
  fi
  git -C "$PKGROOT" pull
  git -C "$PKGROOT" checkout "${REF:-origin/HEAD}"
  if [[ -n $__deploy_key ]]; then
    ssh-add -qD
    eval "$(ssh-agent -k)" >&2
  fi
  (cd "$PKGROOT" && upkg install)
}

main "$@"
