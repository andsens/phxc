#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"
  source "$PKGROOT/lib/mount.sh"

  DOC="bootstrap.sh - Bootstrap images
Usage:
  bootstrap.sh [options] HOSTNAME

Options:
  --imgsize=PATH    Size of the root disk [default: 1.5G]
  --cachepath=PATH  Path to the cache dir [default: \$PKGROOT/cache]
"
# docopt parser below, refresh this parser with `docopt.sh bootstrap.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:208}; usage=${DOC:32:40}; digest=fdd33; shorts=('' '')
longs=(--imgsize --cachepath); argcounts=(1 1); node_0(){ value __imgsize 0; }
node_1(){ value __cachepath 1; }; node_2(){ value HOSTNAME a; }; node_3(){
optional 0 1; }; node_4(){ optional 3; }; node_5(){ required 4 2; }; node_6(){
required 5; }; cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:32:40}" >&2; exit 1; }'; unset var___imgsize \
var___cachepath var_HOSTNAME; parse 6 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}__imgsize" "${prefix}__cachepath" "${prefix}HOSTNAME"
eval "${prefix}"'__imgsize=${var___imgsize:-1.5G}'
eval "${prefix}"'__cachepath=${var___cachepath:-'"'"'$PKGROOT/cache'"'"'}'
eval "${prefix}"'HOSTNAME=${var_HOSTNAME:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__imgsize" "${prefix}__cachepath" "${prefix}HOSTNAME"; done
}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' bootstrap.sh`
  eval "$(docopt "$@")"
  source "$PKGROOT/vars.sh"

  if ! confirm_machine_id bootstrapper; then
    local continue
    read -rp 'Do you want to continue regardless? [y/N]' continue
    [[ $continue =~ [Yy] ]] || fatal "User aborted operation"
  fi
  local env=env ln=ln rm=rm imgpath=$PKGROOT/images/$HOSTNAME.raw
  if [[ $UID != 0 ]]; then
    env="sudo env"
    ln="sudo ln"
    rm="sudo rm"
  fi
  [[ $__cachepath != "\$PKGROOT/cache" ]] || __cachepath=$PKGROOT/cache
  mkdir -p "$(dirname "$imgpath")" "$PKGROOT/logs/fai" "$__cachepath"
  if [[ ! -L "/var/log/fai" ]]; then
    $rm -rf "$PKGROOT/logs/fai"
    $ln -s "$PKGROOT/logs/fai" "/var/log/fai"
  fi
  # shellcheck disable=SC2086
  $env - \
    "PATH=$PATH" \
    "PKGROOT=$PKGROOT" \
    "CACHEPATH=$__cachepath" \
    fai-diskimage --cspace "$PKGROOT/bootstrap" --new --size "${__imgsize:-1.5G}" --hostname "$HOSTNAME" "$imgpath"
  if [[ $UID != 0 ]]; then
    sudo chown "$UID:$UID" "$imgpath"
    sudo chown -R "$UID:$UID" "$__cachepath" "$imgpath"
  fi
}

main "$@"
