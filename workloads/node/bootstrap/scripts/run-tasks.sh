#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")
source "$PKGROOT/.upkg/records.sh/records.sh"
# shellcheck source=workloads/settings/lib/settings-env.shellcheck.sh
source "$PKGROOT/workloads/settings/lib/settings-env.sh"
eval_settings

main() {
  export DEBIAN_FRONTEND=noninteractive

  # Enable backports
  sed -i 's/Suites: bookworm bookworm-updates/Suites: bookworm bookworm-updates bookworm-backports/' /etc/apt/sources.list.d/debian.sources
  # Disable update-initramfs
  cp_tpl --raw /etc/initramfs-tools/update-initramfs.conf
  # Keep old/default config when there is a conflict (i.e. update-initramfs.conf)
  cp_tpl --raw /etc/apt/apt.conf.d/10-dpkg-keep-conf.conf

  PACKAGES=(apt-utils gettext jq yq)
  local taskfile
  for taskfile in "$PKGROOT/workloads/node/bootstrap/tasks.d/"??-*.sh; do
    # shellcheck disable=SC1090
    source "$taskfile"
  done

  readarray -t -d $'\n' -O ${#PACKAGES[@]} PACKAGES < <(printf "%s\n" "${PACKAGES[@]}" | sort -u)
  info "Installing packages: %s" "${PACKAGES[*]}"
  apt-get update -qq
  apt-get install -y -t bookworm-backports --no-install-recommends "${PACKAGES[@]}"
  rm -rf /var/cache/apt/lists/*

  upkg add -g "$PKGROOT/workloads/node/bootstrap/assets/system.upkg.json"

  local task
  for taskfile in "$PKGROOT/workloads/node/bootstrap/tasks.d/"??-*.sh; do
    task=$(basename "$taskfile" .sh)
    task=${task#[0-9][0-9]-}
    task=${task//[^a-z0-9_]/_}
    info "Running %s" "$(basename "$taskfile")"
    if [[ $(type "$task" 2>/dev/null) = "$task is a function"* ]]; then
      eval "$task"
    else
      warning "%s had no task named %s" "$(basename "$taskfile")" "$task"
    fi
  done

  apt-get autoremove -y
  apt-get autoclean
}

cp_tpl() {
  DOC="cp-tpl - Render a template and save it at the corresponding container path
Usage:
  cp-tpl [options] TPLPATH
  cp-tpl [--raw --chmod MODE] TPLPATH...

Options:
  -d --destination PATH  Override the destination path
  --raw                  Don't replace any variables, copy directly
  --chmod MODE           chmod the destination
"
# docopt parser below, refresh this parser with `docopt.sh run-tasks.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034,2154
docopt() { local v='2.0.1'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:329};usage=${DOC:75:74}
digest=a65de;options=('-d --destination 1' ' --raw 0' ' --chmod 1');node_0(){
value __destination 0;};node_1(){ switch __raw 1;};node_2(){ value __chmod 2;}
node_3(){ value TPLPATH a true;};node_4(){ sequence 5 3;};node_5(){ optional 0;}
node_6(){ sequence 7 8;};node_7(){ optional 1 2;};node_8(){ repeatable 3;}
node_9(){ choice 4 6;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" \
"$1" >&2;printf "%s\n" "${DOC:75:74}" >&2;exit 1;}';local \
varnames=(__destination __raw __chmod TPLPATH) varname;for varname in \
"${varnames[@]}"; do unset "var_$varname";done;parse 9 "$@";local \
p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset "$p$varname"
done;if declare -p var_TPLPATH >/dev/null 2>&1; then eval $p'TPLPATH=("${var_T'\
'PLPATH[@]}")';else eval $p'TPLPATH=()';fi;eval $p'__destination=${var___desti'\
'nation:-};'$p'__raw=${var___raw:-false};'$p'__chmod=${var___chmod:-};';local \
docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for \
((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; do declare -p \
"$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' run-tasks.sh`
  eval "$(docopt "$@")"

  local tplpath
  # shellcheck disable=SC2153
  for tplpath in "${TPLPATH[@]}"; do
    tplpath=${tplpath#'/'}
    local dest="${__destination:-"/$tplpath"}"
    mkdir -p "$(dirname "$dest")"
    # shellcheck disable=SC2154
    if $__raw; then
      if [[ -n $__destination ]]; then
        info "Copying template %s to %s" "$tplpath" "$dest"
      else
        info "Copying template %s" "$tplpath"
      fi
      cp "$PKGROOT/workloads/node/bootstrap/assets/$tplpath" "$dest"
    else
      if [[ -n $__destination ]]; then
        info "Rendering template %s to %s" "$tplpath" "$dest"
      else
        info "Rendering template %s" "$tplpath"
      fi
      envsubst <"$PKGROOT/workloads/node/bootstrap/assets/$tplpath" >"$dest"
    fi
    [[ -z $__chmod ]] || chmod "$__chmod" "$dest"
  done
}

main "$@"
