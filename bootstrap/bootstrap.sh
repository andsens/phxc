#!/usr/bin/env bash
# shellcheck source-path=.. disable=2064

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"
  source "$PKGROOT/bootstrap/lib/mount.sh"

  DOC="bootstrap.sh - Bootstrap k3s cluster images
Usage:
  bootstrap create HOSTNAME [IMAGESIZE]
  bootstrap mount IMAGEPATH
  bootstrap boot IMAGEPATH
"
# docopt parser below, refresh this parser with `docopt.sh bootstrap.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:145}; usage=${DOC:44:101}; digest=b5f27; shorts=(); longs=()
argcounts=(); node_0(){ value HOSTNAME a; }; node_1(){ value IMAGESIZE a; }
node_2(){ value IMAGEPATH a; }; node_3(){ _command create; }; node_4(){
_command mount; }; node_5(){ _command boot; }; node_6(){ optional 1; }
node_7(){ required 3 0 6; }; node_8(){ required 4 2; }; node_9(){ required 5 2
}; node_10(){ either 7 8 9; }; node_11(){ required 10; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:44:101}" >&2; exit 1; }'; unset var_HOSTNAME \
var_IMAGESIZE var_IMAGEPATH var_create var_mount var_boot; parse 11 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}HOSTNAME" \
"${prefix}IMAGESIZE" "${prefix}IMAGEPATH" "${prefix}create" "${prefix}mount" \
"${prefix}boot"; eval "${prefix}"'HOSTNAME=${var_HOSTNAME:-}'
eval "${prefix}"'IMAGESIZE=${var_IMAGESIZE:-}'
eval "${prefix}"'IMAGEPATH=${var_IMAGEPATH:-}'
eval "${prefix}"'create=${var_create:-false}'
eval "${prefix}"'mount=${var_mount:-false}'
eval "${prefix}"'boot=${var_boot:-false}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}HOSTNAME" "${prefix}IMAGESIZE" "${prefix}IMAGEPATH" \
"${prefix}create" "${prefix}mount" "${prefix}boot"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' bootstrap.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2154
  if $create; then
    local run_env=env image_path="$PKGROOT/bootstrap/images/$HOSTNAME.raw"
    [[ $UID = 0 ]] || run_env="sudo env"
    mkdir -p "$PKGROOT/bootstrap/images" "$PKGROOT/bootstrap/logs"
    rm -f "$PKGROOT/bootstrap/logs/$HOSTNAME"
    ln -s "/var/log/fai/$HOSTNAME/last" "$PKGROOT/bootstrap/logs/$HOSTNAME"
    # shellcheck disable=SC2086
    $run_env - \
      "PATH=$PATH" \
      "PKGROOT=$PKGROOT" \
      fai-diskimage --cspace "$PKGROOT/bootstrap/config" --new --size "${IMAGESIZE:-1.5G}" --hostname "$HOSTNAME" "$image_path"
    if [[ $UID != 0 ]]; then
      sudo chown "$UID:$UID" "$image_path"
      sudo chown -R "$UID:$UID" "$PKGROOT/bootstrap/cache" "$image_path"
    fi
  elif $mount; then
    local mount_path
    mount_path=$PKGROOT/bootstrap/mnt/$(basename "$IMAGEPATH" .raw)
    mkdir -p "$mount_path"
    mount_image "$IMAGEPATH" "$mount_path"
    info "image %s mounted at %s, press <ENTER> to unmount" "${IMAGEPATH#"$PKGROOT/"}" "${mount_path#"$PKGROOT/"}"
    local _read
    read -rs _read
  elif $boot; then
    kvm -bios /usr/share/ovmf/OVMF.fd \
      -k en-us -smp 2 -cpu host -m 2000 -name "$(basename "$IMAGEPATH" .raw)" \
      -boot order=c -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
      -drive "file=$IMAGEPATH,if=none,format=raw,id=nvme1" -device nvme,serial=SN123450001,drive=nvme1
  fi
}

main "$@"
