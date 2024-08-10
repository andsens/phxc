#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../..")
source "$PKGROOT/.upkg/records.sh/records.sh"
# shellcheck source=workloads/settings/env/settings.shellcheck.sh
source "$PKGROOT/workloads/settings/env/settings.sh"
eval_settings

main() {
  export DEBIAN_FRONTEND=noninteractive

  # Enable backports
  sed -i 's/Suites: bookworm bookworm-updates/Suites: bookworm bookworm-updates bookworm-backports/' /etc/apt/sources.list.d/debian.sources
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
  # Disable update-initramfs
  cp_tpl --raw /etc/initramfs-tools/update-initramfs-disable.conf -d /etc/initramfs-tools/update-initramfs.conf
  # See corresponding file in assets for explanation
  cp_tpl --raw --chmod=0755 /usr/bin/ischroot
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

  info "Building initrd"
  # Re-enable update-initramfs and create initramfs
  cp_tpl --raw /etc/initramfs-tools/update-initramfs.conf
  local kernver
  kernver=$(echo /lib/modules/*)
  kernver=${kernver#'/lib/modules/'}
  update-initramfs -c -k "$kernver"
  # Remove fake ischroot
  rm /usr/bin/ischroot
  # Remove kernel & initramfs symlinks and move real files to fixed location
  rm -f /vmlinuz* /initrd.img*
  mv "/boot/vmlinuz-${kernver}" /boot/vmlinuz
  mv "/boot/initrd.img-${kernver}" /boot/initrd.img
}

cp_tpl() {
  DOC="cp-tpl - Render a template and save it at the corresponding container path
Usage:
  cp-tpl [--raw|--var VAR...] [--chmod MODE -d PATH] TPLPATH
  cp-tpl [--raw|--var VAR...] [--chmod MODE] TPLPATH...

Options:
  -d --destination PATH  Override the destination path
  --raw                  Don't replace any variables, copy directly
  --var VAR              Only replace specified variables
  --chmod MODE           chmod the destination
"
# docopt parser below, refresh this parser with `docopt.sh run-tasks.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034,2154
docopt() { local v='2.0.1'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:436};usage=${DOC:75:123}
digest=dbf91;options=(' --raw 0' ' --var 1' ' --chmod 1' '-d --destination 1')
node_0(){ switch __raw 0;};node_1(){ value __var 1 true;};node_2(){ value \
__chmod 2;};node_3(){ value __destination 3;};node_4(){ value TPLPATH a true;}
node_5(){ sequence 6 9 4;};node_6(){ optional 7;};node_7(){ choice 0 8;}
node_8(){ repeatable 1;};node_9(){ optional 2 3;};node_10(){ sequence 6 11 12;}
node_11(){ optional 2;};node_12(){ repeatable 4;};node_13(){ choice 5 10;};cat \
<<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" \
"${DOC:75:123}" >&2;exit 1;}';local varnames=(__raw __var __chmod \
__destination TPLPATH) varname;for varname in "${varnames[@]}"; do unset \
"var_$varname";done;parse 13 "$@";local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;if declare -p var___var \
>/dev/null 2>&1; then eval $p'__var=("${var___var[@]}")';else eval $p'__var=()'
fi;if declare -p var_TPLPATH >/dev/null 2>&1; then eval $p'TPLPATH=("${var_TPL'\
'PATH[@]}")';else eval $p'TPLPATH=()';fi;eval $p'__raw=${var___raw:-false};'\
$p'__chmod=${var___chmod:-};'$p'__destination=${var___destination:-};';local \
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
      if [[ ${#__var} -gt 0 ]]; then
        local var vars=()
        for var in "${__var[@]}"; do
          vars+=("\$$var")
        done
        envsubst "${vars[*]}" <"$PKGROOT/workloads/node/bootstrap/assets/$tplpath" >"$dest"
      else
        envsubst <"$PKGROOT/workloads/node/bootstrap/assets/$tplpath" >"$dest"
      fi
    fi
    [[ -z $__chmod ]] || chmod "$__chmod" "$dest"
  done
}

main "$@"
