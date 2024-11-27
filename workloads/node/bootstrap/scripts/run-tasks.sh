#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")
source "$PKGROOT/.upkg/records.sh/records.sh"

export DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
export BOOT_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8

main() {
  export DEBIAN_FRONTEND=noninteractive

  # Enable non-free components
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
  apt-get update -qq

  # Install base deps
  # gettext -> envsubst
  apt-get install -y --no-install-recommends gettext

  # Keep old/default config when there is a conflict
  cp_tpl --raw /etc/apt/apt.conf.d/10-dpkg-keep-conf.conf

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
  DOC="cp-tpl - Render a template and save it at the corresponding container path
Usage:
  cp-tpl [--raw|--var VAR...] [--chmod MODE -d PATH] TPLPATH
  cp-tpl [--raw|--var VAR...] [--chmod MODE -r] TPLPATH...

Options:
  -r --recursive         Recursively copy files if TPLPATH is a directory
  -d --destination PATH  Override the destination path
  --raw                  Don't replace any variables, copy directly
  --var VAR              Only replace specified variables
  --chmod MODE           chmod the destination
"
# docopt parser below, refresh this parser with `docopt.sh run-tasks.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034,2154
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:513};usage=${DOC:75:126}
digest=5dbf6;options=(' --raw 0' ' --var 1' ' --chmod 1' '-d --destination 1' \
'-r --recursive 0');node_0(){ switch __raw 0;};node_1(){ value __var 1 true;}
node_2(){ value __chmod 2;};node_3(){ value __destination 3;};node_4(){ switch \
__recursive 4;};node_5(){ value TPLPATH a true;};node_6(){ sequence 7 10 5;}
node_7(){ optional 8;};node_8(){ choice 0 9;};node_9(){ repeatable 1;}
node_10(){ optional 2 3;};node_11(){ sequence 7 12 13;};node_12(){ optional 2 4
};node_13(){ repeatable 5;};node_14(){ choice 6 11;};cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:75:126}" >&2;exit 1
}';local varnames=(__raw __var __chmod __destination __recursive TPLPATH) \
varname;for varname in "${varnames[@]}"; do unset "var_$varname";done;parse 14 \
"$@";local p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset \
"$p$varname";done;if declare -p var___var >/dev/null 2>&1; then eval $p'__var='\
'("${var___var[@]}")';else eval $p'__var=()';fi;if declare -p var_TPLPATH \
>/dev/null 2>&1; then eval $p'TPLPATH=("${var_TPLPATH[@]}")';else eval $p'TPLP'\
'ATH=()';fi;eval $p'__raw=${var___raw:-false};'$p'__chmod=${var___chmod:-};'\
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
      if $__raw; then
        if [[ -n $__destination ]]; then
          info "Copying template %s to %s" "$tplpath" "$dest"
        else
          info "Copying template %s" "$tplpath"
        fi
        cp "$src" "$dest"
      else
        if [[ -n $__destination ]]; then
          info "Rendering template %s to %s" "$tplpath" "$dest"
        else
          info "Rendering template %s" "$tplpath"
        fi
        if [[ ${#__var} -gt 0 ]]; then
          local var vars=()
          for var in "${__var[@]}"; do
            vars+=("\$$var")
          done
          envsubst "${vars[*]}" <"$src" >"$dest"
        else
          envsubst <"$src" >"$dest"
        fi
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

main "$@"
