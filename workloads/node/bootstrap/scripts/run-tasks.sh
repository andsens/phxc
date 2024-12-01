#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")
source "$PKGROOT/.upkg/records.sh/records.sh"

export DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
export BOOT_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8
export DEFAULT_NODE_K3S_MODE=agent
export DEFAULT_NODE_DISK_ENCRYPTION=auto
export DEFAULT_RPI_OTP_OFFSET=0
export DEFAULT_RPI_OTP_LENGTH=8
export DEFAULT_RPI_OTP_KEY_DERIVATION_SUFFIX=1
export DEFAULT_CLUSTER_DOMAIN=phxc.local
export DEFAULT_CLUSTER_CIDRS_POD_IPV4=10.32.0.0/16
export DEFAULT_CLUSTER_CIDRS_POD_IPV6=fdc5:4dcc:7263:cafe:0:32::/96
export DEFAULT_CLUSTER_CIDRS_SVC_IPV4=10.33.0.0/16
export DEFAULT_CLUSTER_CIDRS_SVC_IPV6=fdc5:4dcc:7263:cafe:0:33::/112
export DEFAULT_CLUSTER_CIDRS_LB_IPV4=10.34.0.0/16
export DEFAULT_CLUSTER_CIDRS_LB_IPV6=fdc5:4dcc:7263:cafe:0:34::/112

main() {
  export DEBIAN_FRONTEND=noninteractive

  # Enable non-free components
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
  apt-get update -qq

  # Install base deps
  # gettext -> envsubst
  apt-get install -y --no-install-recommends gettext

  # Keep old/default config when there is a conflict
  cp_tpl /etc/apt/apt.conf.d/10-dpkg-keep-conf.conf

  PACKAGES=(apt-utils jq)
  PACKAGES_TMP=()
  local taskfile
  for taskfile in "$PKGROOT/workloads/node/bootstrap/tasks.d/"??-*.sh; do
    # shellcheck disable=SC1090
    source "$taskfile"
  done

  local all_packages=()
  readarray -t -d $'\n' all_packages < <(printf "%s\n" "${PACKAGES[@]}" "${PACKAGES_TMP[@]}" | sort -u)
  info "Installing packages: %s" "${all_packages[*]}"
  apt-get upgrade -qq
  apt-get install -y --no-install-recommends "${all_packages[@]}"
  rm -rf /var/cache/apt/lists/*

  upkg add -g "$PKGROOT/workloads/node/bootstrap/assets/node.upkg.json"
  upkg add -g "$PKGROOT/workloads/common-context/smallstep.upkg.json"

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

  # `comm -13`: Only remove temp packages that don't also appear in PACKAGES_TMP
  local packages_purge=()
  readarray -t -d $'\n' packages_purge < <(comm -13 <(printf "%s\n" "${PACKAGES[@]}" | sort -u) <(printf "%s\n" "${PACKAGES_TMP[@]}" | sort -u))
  printf "%s\n" "${packages_purge[@]}"
  apt-get purge -y "${packages_purge[@]}"
  apt-get autoremove -y
  apt-get autoclean
}

cp_tpl() {
  DOC="cp_tpl - Render a template and save it at the corresponding container path
Usage:
  cp_tpl [--var VAR...] [--chmod MODE -d PATH] TPLPATH
  cp_tpl [--var VAR...] [--chmod MODE -r] TPLPATH...

Options:
  -r --recursive         Recursively copy files if TPLPATH is a directory
  -d --destination PATH  Override the destination path
  --var VAR              Replace specified variables
  --chmod MODE           chmod the destination
"
# docopt parser below, refresh this parser with `docopt.sh run-tasks.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034,2154
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:428};usage=${DOC:75:114}
digest=2eda5;options=(' --var 1' ' --chmod 1' '-d --destination 1' '-r --recur'\
'sive 0');node_0(){ value __var 0 true;};node_1(){ value __chmod 1;};node_2(){
value __destination 2;};node_3(){ switch __recursive 3;};node_4(){ value \
TPLPATH a true;};node_5(){ sequence 6 8 4;};node_6(){ optional 7;};node_7(){
repeatable 0;};node_8(){ optional 1 2;};node_9(){ sequence 6 10 11;};node_10(){
optional 1 3;};node_11(){ repeatable 4;};node_12(){ choice 5 9;};cat <<<' \
docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" \
"${DOC:75:114}" >&2;exit 1;}';local varnames=(__var __chmod __destination \
__recursive TPLPATH) varname;for varname in "${varnames[@]}"; do unset \
"var_$varname";done;parse 12 "$@";local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;if declare -p var___var \
>/dev/null 2>&1; then eval $p'__var=("${var___var[@]}")';else eval $p'__var=()'
fi;if declare -p var_TPLPATH >/dev/null 2>&1; then eval $p'TPLPATH=("${var_TPL'\
'PATH[@]}")';else eval $p'TPLPATH=()';fi;eval $p'__chmod=${var___chmod:-};'\
$p'__destination=${var___destination:-};'$p'__recursive=${var___recursive:-fal'\
'se};';local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for \
((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; do declare -p \
"$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' run-tasks.sh`
  eval "$(docopt "$@")"

  copy_tpl() {
    local tplpath=${1#'/'}
    local src=$PKGROOT/workloads/node/bootstrap/assets/$tplpath
    local dest="${__destination:-"/$tplpath"}"
    if [[ -d $src ]]; then
      # shellcheck disable=SC2154
      if $__recursive; then
        local subpath
        for subpath in "$src"/*; do
          copy_tpl "${subpath#"$PKGROOT/workloads/node/bootstrap/assets/"}"
        done
      else
        mkdir -p "$(dirname "$dest")"
      fi
    else
      mkdir -p "$(dirname "$dest")"
      # shellcheck disable=SC2154
      if [[ -n $__destination ]]; then
        info "Rendering template %s to %s" "$tplpath" "$dest"
      else
        info "Rendering template %s" "$tplpath"
      fi
      # shellcheck disable=SC2154
      if [[ ${#__var} -gt 0 ]]; then
        local var vars=()
        for var in "${__var[@]}"; do
          vars+=("\$$var")
        done
        envsubst "${vars[*]}" <"$src" >"$dest"
      else
        envsubst "" <"$src" >"$dest"
      fi
      [[ -z $__chmod ]] || chmod "$__chmod" "$dest"
    fi
  }

  local tplpath
  # shellcheck disable=SC2153
  for tplpath in "${TPLPATH[@]}"; do
    copy_tpl "$tplpath"
  done
}


function install_sd_unit() {
  local filepath=$1
  shift
  cp_tpl "_systemd_units/$filepath" -d "/etc/systemd/system/$(basename "$filepath")" "$@"
}

main "$@"
