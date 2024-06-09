#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  # shellcheck disable=SC1091
  source "$PKGROOT/.upkg/records.sh/records.sh"
  # shellcheck source=workloads/settings/lib/settings-env.sh
  source "$PKGROOT/workloads/settings/lib/settings-env.sh"

  DOC="generate-settings-env.shellcheck.sh - Generate a settings file for shellcheck
Usage:
  generate-settings-env.shellcheck.sh
"
# docopt parser below, refresh this parser with `docopt.sh generate-settings-env.shellcheck.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.1'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:122};usage=${DOC:78:44}
digest=53efe;options=();node_0(){ return 0;};cat <<<' docopt_exit() { [[ -n $1 \
]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:78:44}" >&2;exit 1;}';local \
varnames=() varname;for varname in "${varnames[@]}"; do unset "var_$varname"
done;parse 0 "$@";return 0;local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval ;local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' generate-settings-env.shellcheck.sh`
  eval "$(docopt "$@")"

  printf "#!/usr/bin/env bash\n# shellcheck disable=SC2016\n%s" \
    "$(generate_settings "$PKGROOT/settings.template.yaml")" \
    >"$PKGROOT/workloads/settings/lib/settings-env.shellcheck.sh"
}

main "$@"
