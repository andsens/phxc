#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"
  source "$PKGROOT/lib/mount.sh"

  DOC="bootstrap.sh - Bootstrap k3s cluster images
Usage:
  bootstrap create [options] HOSTNAME
  bootstrap mount HOSTNAME
  bootstrap boot HOSTNAME

Options:
  --imgsize=PATH    Size of the root disk [default: 1.5G]
  --cachepath=PATH  Path to the cache dir [default: \$PKGROOT/cache]
"
# docopt parser below, refresh this parser with `docopt.sh bootstrap.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:277}; usage=${DOC:44:97}; digest=af350; shorts=('' '')
longs=(--imgsize --cachepath); argcounts=(1 1); node_0(){ value __imgsize 0; }
node_1(){ value __cachepath 1; }; node_2(){ value HOSTNAME a; }; node_3(){
_command create; }; node_4(){ _command mount; }; node_5(){ _command boot; }
node_6(){ optional 0 1; }; node_7(){ optional 6; }; node_8(){ required 3 7 2; }
node_9(){ required 4 2; }; node_10(){ required 5 2; }; node_11(){ either 8 9 10
}; node_12(){ required 11; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:44:97}" >&2; exit 1
}'; unset var___imgsize var___cachepath var_HOSTNAME var_create var_mount \
var_boot; parse 12 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}__imgsize" "${prefix}__cachepath" "${prefix}HOSTNAME" \
"${prefix}create" "${prefix}mount" "${prefix}boot"
eval "${prefix}"'__imgsize=${var___imgsize:-1.5G}'
eval "${prefix}"'__cachepath=${var___cachepath:-'"'"'$PKGROOT/cache'"'"'}'
eval "${prefix}"'HOSTNAME=${var_HOSTNAME:-}'
eval "${prefix}"'create=${var_create:-false}'
eval "${prefix}"'mount=${var_mount:-false}'
eval "${prefix}"'boot=${var_boot:-false}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__imgsize" "${prefix}__cachepath" "${prefix}HOSTNAME" \
"${prefix}create" "${prefix}mount" "${prefix}boot"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' bootstrap.sh`
  eval "$(docopt "$@")"
  source "$PKGROOT/vars.sh"

  local imgpath=$PKGROOT/images/$HOSTNAME.raw

  # shellcheck disable=SC2154
  if $create; then
    if ! confirm_machine_id bootstrapper; then
      local continue
      read -rp 'Do you want to continue regardless? [y/N]' continue
      [[ $continue =~ [Yy] ]] || fatal "User aborted operation"
    fi
    local env=env ln=ln
    [[ $UID = 0 ]] || env="sudo env"
    [[ $UID = 0 ]] || ln="sudo ln"
    [[ $__cachepath != "\$PKGROOT/cache" ]] || __cachepath=$PKGROOT/cache
    mkdir -p "$(dirname "$imgpath")" "$PKGROOT/logs/fai" "$__cachepath"
    [[ -e "/var/log/fai" ]] || $ln -s "$PKGROOT/logs/fai" "/var/log/fai"
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
  elif $mount; then
    local mount_path
    mount_path=$PKGROOT/mnt/$HOSTNAME
    mkdir -p "$mount_path"
    mount_image "$imgpath" "$mount_path"
    info "image %s mounted at %s, press <ENTER> to unmount" "${imgpath#"$PKGROOT/"}" "${mount_path#"$PKGROOT/"}"
    local _read
    read -rs _read
  elif $boot; then
    kvm -bios /usr/share/ovmf/OVMF.fd \
      -k en-us -smp 2 -cpu host -m 2000 -name "$HOSTNAME" \
      -boot order=c -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
      -drive "file=$imgpath,if=none,format=raw,id=nvme1" -device nvme,serial=SN123450001,drive=nvme1
  fi
}

main "$@"
