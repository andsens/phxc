#!/usr/bin/env bash
# shellcheck source-path=../../.. disable=SC2016
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"
  DOC="create-uefi-boot-image - Create an UEFI boot image from a container tar export
Usage:
  create-uefi-boot-image [options] MACHINE

Options:
  -f --format FORMAT  The desired image format [default: raw]
"
# docopt parser below, refresh this parser with `docopt.sh create-uefi-boot-image.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:200};usage=${DOC:79:49};digest=1bbcb;options=('-f --format'\
' 1');node_0(){ value __format 0;};node_1(){ value MACHINE a;};node_2(){
optional 0;};node_3(){ sequence 2 1;};cat <<<' docopt_exit() { [[ -n $1 ]] && \
printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:79:49}" >&2;exit 1;}';local \
varnames=(__format MACHINE) varname;for varname in "${varnames[@]}"; do unset \
"var_$varname";done;parse 3 "$@";local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval $p'__format=${var___format:-'\
'raw};'$p'MACHINE=${var_MACHINE:-};';local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 \
]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in \
"${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' create-uefi-boot-image.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2153
  alias_machine "$MACHINE"

  # shellcheck disable=SC2154
  local \
    tar=/images/snapshots/$MACHINE.tar \
    image_tmp=/images/uefi/$MACHINE.tmp.raw \
    image_dest=/images/uefi/$MACHINE.$__format \
    efi_size=64 disk_size_mib tar_size_b sectors_per_mib


  tar_size_b=$(stat -c %s "$tar")
  sectors_per_mib=$(( 1024 * 1024 / 512 ))
  secondary_gpt_sectors=33
  # Disk size = 5 * Tar size
  disk_size_mib=$((tar_size_b * 5 / 1024 / 1024))

  # SD_GPT_ESP=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
  # SD_GPT_ROOT_X86_64=4f68bce3-e8cd-4db1-96e7-fbcaf984b709

  rm -f "$image_tmp"
  truncate --size ${disk_size_mib}M "$image_tmp"

  sfdisk "$image_tmp" <<EOF
label: gpt
label-id: $(uuidgen)

start=$(( 1 * sectors_per_mib )), size=$(( efi_size * sectors_per_mib )), type=U, bootable
start=$(( ( 1 + efi_size ) * sectors_per_mib )), size=$(( ( disk_size_mib - ( 1 + efi_size ) ) * sectors_per_mib - secondary_gpt_sectors )), type=L
EOF

  LOOP=$(losetup --find --partscan --show "$image_tmp")
  trap_append detach EXIT
  local detach_trap=$TRAP_POINTER

  local efi_dev=${LOOP}p1 root_dev=${LOOP}p2

  mkfs.vfat "$efi_dev"
  mkfs.ext4 "$root_dev"
  tune2fs -c 0 -i 0 "$root_dev"

  mkdir /mnt/image
  mount -t auto "$root_dev" /mnt/image
  MOUNTS+=(/mnt/image)
  trap_prepend 'unmount_all' EXIT
  local umount_trap=$TRAP_POINTER

  local layer
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "$tar" manifest.json)); do
    tar -xOf "$tar" "$layer" | tar -xz -C /mnt/image
  done


  mount --bind /dev /mnt/image/dev
  MOUNTS+=(/mnt/image/dev)
  mount -t devpts none /mnt/image/dev/pts
  MOUNTS+=(/mnt/image/dev/pts)
  mount -t proc none /mnt/image/proc
  MOUNTS+=(/mnt/image/proc)
  mount -t sysfs none /mnt/image/sys
  MOUNTS+=(/mnt/image/sys)

  local root_uuid efi_uuid
  # It should be possible to use https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
  # with https://manpages.debian.org/bookworm/systemd/systemd-gpt-auto-generator.8.en.html
  # in order to be able to completely omit both /etc/fstab and the kernel root param
  # root_uuid=$(chroot /mnt/image systemd-id128 -u --app-specific=$SD_GPT_ROOT_X86_64 machine-id)
  # sfdisk --part-uuid "$image_tmp" 2 "$root_uuid"
  efi_uuid=$(blkid -s UUID -o value "${LOOP}p1")
  root_uuid=$(blkid -s UUID -o value "${LOOP}p2")

  mkdir /mnt/image/boot/efi
  mount -t auto "$efi_dev" /mnt/image/boot/efi
  MOUNTS+=(/mnt/image/boot/efi)

  printf "root=UUID=%s\n" "$root_uuid" >/mnt/image/etc/kernel/cmdline
  printf '%-15s /               ext4    rw,discard,barrier=0,noatime,errors=remount-ro  0       1
%-15s /boot/efi       vfat    defaults        0       2
' "UUID=$root_uuid" "UUID=$efi_uuid" >>/mnt/image/etc/fstab
# ' "UUID=$root_uuid" "UUID=$SD_GPT_ESP" >/mnt/image/etc/fstab

  chroot /mnt/image bootctl --no-variables install
  chroot /mnt/image update-initramfs -u -k all

  trap_remove "$umount_trap"
  unmount_all
  zerofree "$root_dev"

  trap_remove "$detach_trap"
  detach

  # shellcheck disable=SC2154
  if [[ $__format != raw ]]; then
    local image_raw=$image_tmp
    image_tmp=${image_tmp%.raw}.$__format
    case $format in
      vhdx) qemu-img convert -p -f raw -O "$__format" -o subformat=dynamic "$image_raw" "$image_tmp" ;;
      *) qemu-img convert -p -f raw -O "$__format" "$image_raw" "$image_tmp" ;;
    esac
    rm -f "$image_raw"
  fi
  mv "$image_tmp" "$image_dest"
}

unmount_all() {
  local indices i
    # shellcheck disable=SC2206
  for ((i=${#MOUNTS[@]} - 1; i >= 0; i--)) ; do
    umount -q "${MOUNTS[i]}"
  done
}

detach() {
  losetup --detach "$LOOP"
}

main "$@"
