#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

main() {
  # shellcheck disable=SC1091
  source "$PKGROOT/.upkg/records.sh/records.sh"
  # shellcheck disable=SC1091
  source "$PKGROOT/.upkg/trap.sh/trap.sh"
  DOC="create-boot-images - Create PXE & UEFI boot image from a container export
Usage:
  create-boot-images [-a ARCH]

Options:
  -a --arch ARCH  Processor architecture of the image [default: amd64]
"
# docopt parser below, refresh this parser with `docopt.sh create-boot-images.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.1'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:192};usage=${DOC:74:37}
digest=aea8f;options=('-a --arch 1');node_0(){ value __arch 0;};node_1(){
optional 0;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:74:37}" >&2;exit 1;}';local varnames=(__arch) varname;for \
varname in "${varnames[@]}"; do unset "var_$varname";done;parse 1 "$@";local \
p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset "$p$varname"
done;eval $p'__arch=${var___arch:-amd64};';local docopt_i=1;[[ $BASH_VERSION \
=~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in \
"${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' create-boot-images.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2154
  local \
    tar=/images/snapshots/$__arch.tar \
    pxedir=/images/pxe/$__arch \
    uefidir=/images/uefi

  WORKDIR=$(mktemp -d)
  mkdir "$WORKDIR/root"
  # shellcheck disable=SC2016
  trap_append 'rm -rf "$WORKDIR"' EXIT

  info "Extracting container export"
  local layer
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "$tar" manifest.json)); do
    tar -xOf "$tar" "$layer" | tar -xz -C "$WORKDIR/root"
  done
  # During bootstrapping with kaniko these file can't be removed/overwritten,
  # instead we do it when creating the images
  rm "$WORKDIR/root/etc/hostname" "$WORKDIR/root/etc/resolv.conf"
  cp "/assets/etc-hosts" "$WORKDIR/root/etc/hosts"

  # PXE Boot #

  mkdir -p "$pxedir"

  info "Extracting kernel image"
  mv "$WORKDIR/root/boot/vmlinuz" "$pxedir/vmlinuz.tmp"
  mv "$WORKDIR/root/boot/initrd.img" "$pxedir/initrd.img.tmp"
  mv "$WORKDIR/root/boot/vmlinuz.unsigned.efi" "$pxedir/vmlinuz.unsigned.efi.tmp"

  info "Creating squashfs image"
  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs "$WORKDIR/root" "$pxedir/root.img.tmp" -noappend -quiet $noprogress

  ### UEFI Boot ###

  info "Generate node settings"
  mkdir "$WORKDIR/node-settings"
  local file node_settings_size_b=0
  for file in /node-settings/*; do
    node_settings_size_b=$(( node_settings_size_b + $(stat -c %s "$file") ))
    cp "$file" "$WORKDIR/node-settings/$(basename "$file" | sed s/:/-/g)"
  done

  dd if=/dev/random bs=32 count=1 >"$WORKDIR/random-seed"

  local sector_size_b=512 gpt_size_b fs_table_size_b partition_offset_b partition_size_b disk_size_kib
  gpt_size_b=$((33 * sector_size_b))
  fs_table_size_b=$(( 1024 * 1024 )) # Total guess, but should be enough
  config_size_b=1024 # Same, should be fine
  partition_offset_b=$((1024 * 1024))
  # efi * 2 : The EFI boot loader is copied to two different destinations
  # stat -c %s : Size in bytes of the file
  # ... (sector_size_b - 1) ) / sector_size_b * sector_size_b : Round to next sector
  partition_size_b=$((
    (
      fs_table_size_b +
      config_size_b +
      node_settings_size_b +
      $(stat -c %s "$pxedir/vmlinuz.unsigned.efi.tmp") +
      $(stat -c %s "$pxedir/root.img.tmp") +
      (sector_size_b - 1)
    ) / sector_size_b * sector_size_b
  ))
  disk_size_kib=$((
    (
      partition_offset_b +
      partition_size_b +
      gpt_size_b +
      1023
    ) / 1024
  ))

  # Fixed, so we can find it when we need to mount the EFI partition during init
  DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
  ESP_UUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
  rm -f "$uefidir/$__arch.raw.tmp"

  info "Creating UEFI boot image"
  guestfish -N "$uefidir/$__arch.raw.tmp"=disk:${disk_size_kib}K -- <<EOF
part-init /dev/sda gpt
part-add /dev/sda primary $(( partition_offset_b / sector_size_b )) $(( (partition_offset_b + partition_size_b ) / sector_size_b - 1 ))
part-set-bootable /dev/sda 1 true
part-set-disk-guid /dev/sda $DISK_UUID
part-set-gpt-guid /dev/sda 1 $ESP_UUID

mkfs vfat /dev/sda1
mount /dev/sda1 /

mkdir-p /EFI/BOOT
copy-in "$pxedir/vmlinuz.unsigned.efi.tmp" /EFI/BOOT/
mv /EFI/BOOT/vmlinuz.unsigned.efi.tmp /EFI/BOOT/BOOTX64.EFI

mkdir-p /home-cluster
copy-in "$pxedir/root.img.tmp" /home-cluster/
mv /home-cluster/root.img.tmp /home-cluster/root.img
copy-in "$WORKDIR/node-settings" /home-cluster/
EOF

  ### Finish up by moving everything to the right place

  mv "$uefidir/$__arch.raw.tmp" "$uefidir/$__arch.raw"
  mv "$pxedir/root.img.tmp" "$pxedir/root.img"
  mv "$pxedir/vmlinuz.tmp" "$pxedir/vmlinuz"
  mv "$pxedir/initrd.img.tmp" "$pxedir/initrd.img"
  mv "$pxedir/vmlinuz.unsigned.efi.tmp" "$pxedir/vmlinuz.unsigned.efi"
}


main "$@"
