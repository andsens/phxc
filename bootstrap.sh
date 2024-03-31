#!/usr/bin/env bash
# shellcheck source-path=..

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/bootstrap/lib/mount.sh"

  DOC="bootstrap.sh - Bootstrap k3s cluster images
Usage:
  bootstrap create [options] HOSTNAME [IMGPATH]
  bootstrap mount IMGPATH
  bootstrap boot IMGPATH

Options:
  --imgsize=PATH    Size of the root disk [default: 1.5G]
  --varspath=PATH   Path to vars.sh [default: \$PKGROOT/vars.sh]
  --cachepath=PATH  Path to the cache dir [default: \$PKGROOT/bootstrap/cache]
"
# docopt parser below, refresh this parser with `docopt.sh bootstrap.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:359}; usage=${DOC:44:105}; digest=dd18e; shorts=('' '' '')
longs=(--varspath --cachepath --imgsize); argcounts=(1 1 1); node_0(){
value __varspath 0; }; node_1(){ value __cachepath 1; }; node_2(){
value __imgsize 2; }; node_3(){ value HOSTNAME a; }; node_4(){ value IMGPATH a
}; node_5(){ _command create; }; node_6(){ _command mount; }; node_7(){
_command boot; }; node_8(){ optional 0 1 2; }; node_9(){ optional 8; }
node_10(){ optional 4; }; node_11(){ required 5 9 3 10; }; node_12(){
required 6 4; }; node_13(){ required 7 4; }; node_14(){ either 11 12 13; }
node_15(){ required 14; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:44:105}" >&2; exit 1
}'; unset var___varspath var___cachepath var___imgsize var_HOSTNAME \
var_IMGPATH var_create var_mount var_boot; parse 15 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}__varspath" \
"${prefix}__cachepath" "${prefix}__imgsize" "${prefix}HOSTNAME" \
"${prefix}IMGPATH" "${prefix}create" "${prefix}mount" "${prefix}boot"
eval "${prefix}"'__varspath=${var___varspath:-'"'"'$PKGROOT/vars.sh'"'"'}'
eval "${prefix}"'__cachepath=${var___cachepath:-'"'"'$PKGROOT/bootstrap/cache'"'"'}'
eval "${prefix}"'__imgsize=${var___imgsize:-1.5G}'
eval "${prefix}"'HOSTNAME=${var_HOSTNAME:-}'
eval "${prefix}"'IMGPATH=${var_IMGPATH:-}'
eval "${prefix}"'create=${var_create:-false}'
eval "${prefix}"'mount=${var_mount:-false}'
eval "${prefix}"'boot=${var_boot:-false}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__varspath" "${prefix}__cachepath" "${prefix}__imgsize" \
"${prefix}HOSTNAME" "${prefix}IMGPATH" "${prefix}create" "${prefix}mount" \
"${prefix}boot"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' bootstrap.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2154
  if $create; then
    local run_env=env
    [[ $UID = 0 ]] || run_env="sudo env"
    IMGPATH=${IMGPATH:-"$PKGROOT/bootstrap/images/$HOSTNAME.raw"}
    [[ $__varspath != "\$PKGROOT/vars.sh" ]] || __varspath=$PKGROOT/vars.sh
    [[ $__cachepath != "\$PKGROOT/bootstrap/cache" ]] || __cachepath=$PKGROOT/bootstrap/cache
    mkdir -p "$(dirname "$IMGPATH")" "$PKGROOT/bootstrap/logs"
    rm -f "$PKGROOT/bootstrap/logs/$HOSTNAME"
    ln -s "/var/log/fai/$HOSTNAME/last" "$PKGROOT/bootstrap/logs/$HOSTNAME"
    # shellcheck disable=SC2086
    $run_env - \
      "PATH=$PATH" \
      "PKGROOT=$PKGROOT" \
      "VARSPATH=$__varspath" \
      "CACHEPATH=$__cachepath" \
      fai-diskimage --cspace "$PKGROOT/bootstrap/config" --new --size "${__imgsize:-1.5G}" --hostname "$HOSTNAME" "$IMGPATH"
    if [[ $UID != 0 ]]; then
      sudo chown "$UID:$UID" "$IMGPATH"
      sudo chown -R "$UID:$UID" "$__cachepath" "$IMGPATH"
    fi
  elif $mount; then
    local mount_path
    mount_path=$PKGROOT/bootstrap/mnt/$(basename "$IMGPATH" .raw)
    mkdir -p "$mount_path"
    mount_image "$IMGPATH" "$mount_path"
    info "image %s mounted at %s, press <ENTER> to unmount" "${IMGPATH#"$PKGROOT/"}" "${mount_path#"$PKGROOT/"}"
    local _read
    read -rs _read
  elif $boot; then
    kvm -bios /usr/share/ovmf/OVMF.fd \
      -k en-us -smp 2 -cpu host -m 2000 -name "$(basename "$IMGPATH" .raw)" \
      -boot order=c -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
      -drive "file=$IMGPATH,if=none,format=raw,id=nvme1" -device nvme,serial=SN123450001,drive=nvme1
  fi
}

main "$@"
