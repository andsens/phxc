#!/usr/bin/env bash
# shellcheck source-path=../../.. disable=SC2016
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"
  DOC="create-pxe-boot-image - Create a PXE boot image from a container tar export
Usage:
  create-pxe-boot-image [options] MACHINE
"
# docopt parser below, refresh this parser with `docopt.sh create-pxe-boot-image.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:124};usage=${DOC:76:48};digest=9dc03;options=();node_0(){
value MACHINE a;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:76:48}" >&2;exit 1;}';local varnames=(MACHINE) varname
for varname in "${varnames[@]}"; do unset "var_$varname";done;parse 0 "$@"
local p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset \
"$p$varname";done;eval $p'MACHINE=${var_MACHINE:-};';local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' create-pxe-boot-image.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2153
  alias_machine "$MACHINE"

  local \
    tar=/images/snapshots/$MACHINE.tar \
    pxedir=/images/pxe/$MACHINE

  TMPROOT=$(mktemp -d)
  trap_append 'rm -rf "$TMPROOT"' EXIT

  info "Extracting container export"
  local layer
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "$tar" manifest.json)); do
    tar -xOf "$tar" "$layer" | tar -xz -C "$TMPROOT"
  done

  mkdir -p "$pxedir"

  info "Creating squashfs image"
  mksquashfs "$TMPROOT" "$pxedir/root.tmp.img" -noappend -quiet

  info "Extracting kernel image"
  cp -L "$TMPROOT/vmlinuz" "$pxedir/vmlinuz.tmp"
  cp -L "$TMPROOT/initrd.img" "$pxedir/initrd.img.tmp"

  mv "$pxedir/root.tmp.img" "$pxedir/root.img"
  mv "$pxedir/vmlinuz.tmp" "$pxedir/vmlinuz"
  mv "$pxedir/initrd.img.tmp" "$pxedir/initrd.img"
}
main "$@"
