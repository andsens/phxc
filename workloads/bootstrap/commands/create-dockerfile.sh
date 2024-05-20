#!/usr/bin/env bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"

  DOC="create-dockerfile - Concatenate Dockerfiles for a machine build
Usage:
  create-dockerfile MACHINE
"
# docopt parser below, refresh this parser with `docopt.sh create-dockerfile.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0a3' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:98}
usage=${DOC:64:34};digest=cf50e;options=();node_0(){ value MACHINE a;};cat \
<<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" \
"${DOC:64:34}" >&2;exit 1;}';local varnames=(MACHINE) varname;for varname in \
"${varnames[@]}"; do unset "var_$varname";done;parse 0 "$@";local \
p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset "$p$varname"
done;eval $p'MACHINE=${var_MACHINE:-};';local docopt_i=1;[[ $BASH_VERSION =~ \
^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in \
"${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' create-dockerfile.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2153
  alias_machine "$MACHINE"
  printf "%s\n" "$(for layer in $MACHINE_LAYERS; do cat "$PKGROOT/workloads/bootstrap/containers/$layer/Dockerfile"; done)" > "$PKGROOT/images/$MACHINE.Dockerfile"
}

main "$@"
