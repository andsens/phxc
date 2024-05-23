#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"

  DOC="generate-shellcheck-settings.sh - Generate a settings file for shellcheck
Usage:
  generate-shellcheck-settings.sh
"
# docopt parser below, refresh this parser with `docopt.sh generate-shellcheck-settings.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0a3' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:114};usage=${DOC:74:40};digest=a72a2;options=();node_0(){
return 0;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:74:40}" >&2;exit 1;}';local varnames=() varname;for \
varname in "${varnames[@]}"; do unset "var_$varname";done;parse 0 "$@";return 0
local p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset \
"$p$varname";done;eval ;local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && \
docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; \
do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' generate-shellcheck-settings.sh`
  eval "$(docopt "$@")"

  printf "#!/usr/bin/env bash\n# shellcheck disable=SC2016\n%s" \
    "$(generate_settings "$PKGROOT/settings.template.yaml")" \
    >"$PKGROOT/workloads/settings/lib/settings.shellcheck.sh"

}

main "$@"
