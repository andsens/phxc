#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  confirm_container_build

  export DEBIAN_FRONTEND=noninteractive

  apt-get update -qq
  apt-get -qq install --no-install-recommends apt-utils gettext jq yq >/dev/null

  source "$PKGROOT/lib/common.sh"
  # shellcheck disable=SC2153
  alias_machine "$MACHINE"

  PACKAGES=()
  local layer layer_file layer_files=()
  for layer in $MACHINE_LAYERS; do
    if layer_file=$(compgen -G "$PKGROOT/workloads/bootstrap/layers/??-$layer.sh"); then
      # shellcheck disable=SC1090
      source "$layer_file"
      layer_files+=("$layer_file")
    fi
  done
  readarray -t -d $'\n' layer_files < <(printf "%s\n" "${layer_files[@]}" | sort)

  readarray -t -d $'\n' PACKAGES < <(printf "%s\n" "${PACKAGES[@]}" | sort -u)
  info "Installing packages: %s" "${PACKAGES[*]}"
  apt-get -qq install --no-install-recommends "${PACKAGES[@]}" >/dev/null
  rm -rf /var/cache/apt/lists/*

  for layerfile in "${layer_files[@]}"; do
    layer=$(basename "$layerfile" .sh)
    layer=${layer#[0-9][0-9]-}
    layer=${layer//[^a-z0-9_]/_}
    if [[ $(type "$layer" 2>/dev/null) = "$layer is a function"* ]]; then
      info "Applying layer '%s'" "$layer"
      eval "$layer"
    fi
  done

  update-initramfs -u -k all
}

confirm_container_build() {
  if [[ -f /proc/1/cgroup ]]; then
    [[ "$(</proc/1/cgroup)" != *:cpuset:/docker/* ]] || return 0
  fi
  [[ ! -e /kaniko ]] || return 0
  error "This script is intended to be run on during the container build phase"
  printf "Do you want to continue regardless? [y/N]" >&2
  if ${HOME_CLUSTER_IGNORE_CONTAINER_BUILD:-false}; then
    printf " \$HOME_CLUSTER_IGNORE_CONTAINER_BUILD=true, continuing..."
  elif [[ ! -t 1 ]]; then
    printf "stdin is not a tty and HOME_CLUSTER_IGNORE_CONTAINER_BUILD!=true, aborting...\n" >&2
    return 1
  else
    local continue
    read -r continue
    [[ $continue =~ [Yy] ]] || fatal "User aborted operation"
    return 0
  fi
}

cp_tpl() {
  DOC="cp-tpl - Render a template and save it at the corresponding container path
Usage:
  cp-tpl [options] TPLPATH

Options:
  -d --destination PATH  Override the destination path
  --raw                  Don't replace any variables, copy directly
  --chmod MODE           chmod the destination
"
# docopt parser below, refresh this parser with `docopt.sh cp-tpl`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:288};usage=${DOC:75:33};digest=d0b8e;options=('-d --destin'\
'ation 1' ' --raw 0' ' --chmod 1');node_0(){ value __destination 0;};node_1(){
switch __raw 1;};node_2(){ value __chmod 2;};node_3(){ value TPLPATH a;}
node_4(){ optional 0 1 2;};node_5(){ sequence 4 3;};cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:75:33}" >&2;exit 1;}'
local varnames=(__destination __raw __chmod TPLPATH) varname;for varname in \
"${varnames[@]}"; do unset "var_$varname";done;parse 5 "$@";local \
p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset "$p$varname"
done;eval $p'__destination=${var___destination:-};'$p'__raw=${var___raw:-false'\
'};'$p'__chmod=${var___chmod:-};'$p'TPLPATH=${var_TPLPATH:-};';local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do
for varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' cp-tpl`
  eval "$(docopt "$@")"

  local dest="${__destination:-$TPLPATH}"
  mkdir -p "$(dirname "$dest")"
  # shellcheck disable=SC2154
  if $__raw; then
    cp "$PKGROOT/workloads/bootstrap/assets/${TPLPATH#/}" "$dest"
  else
    envsubst <"$PKGROOT/workloads/bootstrap/assets/${TPLPATH#/}" >"$dest"
  fi
  [[ -z $__chmod ]] || chmod "$__chmod" "$dest"
}

main "$@"
