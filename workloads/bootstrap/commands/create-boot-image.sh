#!/usr/bin/env bash
# shellcheck source-path=../../..
# No -E, we have an EXIT trap in main() and a different one in create_boot_image
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"
  DOC="create-boot-image - Build an image for a machine by layering container images
Usage:
  create-boot-image [options] TARPATH

Options:
  -f --format FORMAT  The desired image format [default: raw]
"
# docopt parser below, refresh this parser with `docopt.sh create-boot-image.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0a3' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:194};usage=${DOC:78:44};digest=31ece;options=('-f --format'\
' 1');node_0(){ value __format 0;};node_1(){ value TARPATH a;};node_2(){
optional 0;};node_3(){ sequence 2 1;};cat <<<' docopt_exit() { [[ -n $1 ]] && \
printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:78:44}" >&2;exit 1;}';local \
varnames=(__format TARPATH) varname;for varname in "${varnames[@]}"; do unset \
"var_$varname";done;parse 3 "$@";local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval $p'__format=${var___format:-'\
'raw};'$p'TARPATH=${var_TARPATH:-};';local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 \
]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in \
"${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' create-boot-image.sh`
  eval "$(docopt "$@")"

  local tar=$1 efi_size=64 disk_size_mib tar_size_b image
  tar_size_b=$(stat -c %s "$tar")
  # Disk size = 5 * Tar size
  disk_size_mib=$((tar_size_b * 5 / 1024 / 1024))
  image=$(dirname "$TARPATH")/$(basename "$TARPATH" .tar).raw

  EFI_LOOP=/dev/loop5
  ROOT_LOOP=/dev/loop6

  truncate --size ${disk_size_mib}M "$image"

  parted -s -a optimal "$image" mklabel gpt mkpart primary fat32 1MiB $(( 1 + efi_size ))MiB set 1 esp on
  parted -s -a optimal "$image" mkpart primary ext4 $(( 1 + efi_size ))MiB $(( disk_size_mib - 1 ))MiB

  trap 'set +e; unmount_all; detach_all; rm -rf "$TMP"' EXIT

  losetup -b 4K -o 1MiB --sizelimit ${efi_size}MiB $EFI_LOOP "$image"
  losetup -b 4K -o $(( 1 + efi_size ))MiB --sizelimit $(( disk_size_mib - 1 - efi_size - 1 ))MiB $ROOT_LOOP "$image"
  mkfs.vfat $EFI_LOOP
  mkfs.ext4 $ROOT_LOOP
  tune2fs -c 0 -i 0 $ROOT_LOOP

  mkdir /mnt/image
  mount -t auto $ROOT_LOOP /mnt/image

  local layer
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "$tar" manifest.json)); do
    tar -xOf "$tar" "$layer" | tar -xz -C /mnt/image
  done

  mount --bind /dev /mnt/image/dev
  mount -t devpts none /mnt/image/dev/pts
  mount -t proc none /mnt/image/proc
  mount -t sysfs none /mnt/image/sys

  mkdir /mnt/image/boot/efi
  mount -t auto $EFI_LOOP /mnt/image/boot/efi

  mkdir -p /dev/disk/by-uuid
  ln -s "../../$(basename $EFI_LOOP)" "/mnt/image/dev/disk/by-uuid/$(blkid -s UUID -o value $EFI_LOOP)"
  ln -s "../../$(basename $ROOT_LOOP)" "/mnt/image/dev/disk/by-uuid/$(blkid -s UUID -o value $ROOT_LOOP)"
  printf "root=UUID=%s\n" "$(blkid -s UUID -o value $ROOT_LOOP)" >/mnt/image/etc/kernel/cmdline
  printf '# /etc/fstab: static file system information.
#
# <file sys>    <mount point>   <type>  <options>       <dump>  <pass>
%-15s /               ext4    rw,discard,barrier=0,noatime,errors=remount-ro  0       1
%-15s /boot/efi       vfat    defaults        0       2
' "UUID=$(blkid -s UUID -o value $ROOT_LOOP)" "UUID=$(blkid -s UUID -o value $EFI_LOOP)" >/mnt/image/etc/fstab

  chroot /mnt/image bootctl install
  chroot /mnt/image update-initramfs -u -k all
  unmount_all
  trap 'detach_all; rm -rf "$TMP"' EXIT
  zerofree $ROOT_LOOP
  detach_all
  trap 'rm -rf "$TMP"' EXIT

  # shellcheck disable=SC2154
  if [[ $__format != raw ]]; then
    local old_image=$image
    image=$(basename "$image" .raw).$__format
    qemu-img convert -p -f raw -O "$__format" -o subformat=dynamic "$old_image" "$image"
    rm -f "$old_image"
  fi
}

unmount_all() {
  umount -q /mnt/image/sys
  umount -q /mnt/image/proc
  umount -q /mnt/image/dev/pts
  umount -q /mnt/image/dev
  umount -q /mnt/image/boot/efi
  umount -q /mnt/image
}

detach_all() {
  losetup --detach "$EFI_LOOP"
  losetup --detach "$ROOT_LOOP"
}

main "$@"
