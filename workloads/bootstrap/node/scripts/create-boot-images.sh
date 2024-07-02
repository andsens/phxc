#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"
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

  mkdir -p /workspace/root

  info "Extracting container export"
  local layer
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "$tar" manifest.json)); do
    tar -xOf "$tar" "$layer" | tar -xz -C /workspace/root
  done
  # During bootstrapping with kaniko these file can't be removed/overwritten,
  # instead we do it when creating the image
  rm /workspace/root/etc/hostname /workspace/root/etc/resolv.conf
  cp /assets/etc-hosts /workspace/root/etc/hosts
  # Revert the disabling of initramfs creation
  cp /assets/etc-initramfs-tools-update-initramfs.conf /workspace/root/etc/initramfs-tools/update-initramfs.conf

  local vmlinuz initrd
  vmlinuz=/$(readlink /workspace/root/vmlinuz)
  initrd=/$(readlink /workspace/root/initrd.img)
  # Remove kernel symlinks
  rm /workspace/root/initrd.img* /workspace/root/vmlinuz*
  # Move boot dir out of the way before creating squashfs image
  mv /workspace/root/boot /workspace/boot
  # Convert secureboot cert from PEM to DER and save to root disk for enrollment by enroll-sb-cert
  mkdir /workspace/root/etc/home-cluster
  step certificate format /secureboot/tls.crt >/workspace/root/etc/home-cluster/secureboot.der

  info "Creating squashfs image"
  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs /workspace/root /workspace/root.img -noappend -quiet $noprogress

  # Move boot dir back into place
  mv /workspace/boot /workspace/root/boot

  # Hash the root image so we can verify it during boot
  local rootimg_checksum
  rootimg_checksum=$(sha256sum /workspace/root.img | cut -d ' ' -f1)

  info "Creating unified kernel image"
  local kernver
  kernver=${vmlinuz#'/boot/vmlinuz-'}
  chroot /workspace/root update-initramfs -c -k "$kernver"
  cp -r /secureboot /workspace/root/secureboot
  chroot /workspace/root /lib/systemd/ukify build \
    --uname="$kernver" \
    --linux="$vmlinuz" \
    --initrd="$initrd" \
    --cmdline="root=/run/initramfs/root.img root_sha256=$rootimg_checksum bootserver=${CLUSTER_BOOTSERVER_FIXEDIPV4} noresume" \
    --signtool=sbsign \
    --secureboot-private-key=/secureboot/tls.key \
    --secureboot-certificate=/secureboot/tls.crt \
    --output=/boot/vmlinuz.efi
  mv /workspace/root/boot/vmlinuz.efi /workspace/vmlinuz.efi

  ### UEFI Boot ###

  info "Generating node settings"
  mkdir /workspace/node-settings
  local file node_settings_size_b=0
  for file in /node-settings/*; do
    node_settings_size_b=$(( node_settings_size_b + $(stat -c %s "$file") ))
    cp "$file" "/workspace/node-settings/$(basename "$file" | sed s/:/-/g)"
  done

  dd if=/dev/random bs=32 count=1 >/workspace/random-seed

  local sector_size_b=512 gpt_size_b fs_table_size_b partition_offset_b partition_size_b disk_size_kib
  gpt_size_b=$((33 * sector_size_b))
  fs_table_size_b=$(( 1024 * 1024 )) # Total guess, but should be enough
  partition_offset_b=$((1024 * 1024))
  # efi * 2 : The EFI boot loader is copied to two different destinations
  # stat -c %s : Size in bytes of the file
  # ... (sector_size_b - 1) ) / sector_size_b * sector_size_b : Round to next sector
  partition_size_b=$((
    (
      fs_table_size_b +
      node_settings_size_b +
      $(stat -c %s /usr/lib/shim/shimx64.efi.signed) +
      $(stat -c %s /usr/lib/shim/mmx64.efi.signed) +
      $(stat -c %s /workspace/vmlinuz.efi) +
      $(stat -c %s /workspace/root/etc/home-cluster/secureboot.der) +
      $(stat -c %s /workspace/root.img) +
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

  info "Creating UEFI boot image"
  local shimname grubname
  case $__arch in
    amd64)
      shimname=BOOTX64.EFI
      grubname=grubx64.efi
      ;;
  esac

  guestfish -xN /workspace/disk.raw=disk:${disk_size_kib}K -- <<EOF
part-init /dev/sda gpt
part-add /dev/sda primary $(( partition_offset_b / sector_size_b )) $(( (partition_offset_b + partition_size_b ) / sector_size_b - 1 ))
part-set-bootable /dev/sda 1 true
part-set-disk-guid /dev/sda $DISK_UUID
part-set-gpt-guid /dev/sda 1 $ESP_UUID

mkfs vfat /dev/sda1
mount /dev/sda1 /

mkdir-p /EFI/BOOT
copy-in /usr/lib/shim/shimx64.efi.signed /EFI/BOOT/
mv /EFI/BOOT/shimx64.efi.signed /EFI/BOOT/$shimname
copy-in /usr/lib/shim/mmx64.efi.signed /EFI/BOOT/
mv /EFI/BOOT/mmx64.efi.signed /EFI/BOOT/mmx64.efi
copy-in /workspace/vmlinuz.efi /EFI/BOOT/
mv /EFI/BOOT/vmlinuz.efi /EFI/BOOT/$grubname

mkdir-p /home-cluster
copy-in /workspace/root/etc/home-cluster/secureboot.der /home-cluster/
copy-in /workspace/root.img /home-cluster/
copy-in /workspace/node-settings /home-cluster/
EOF

  ### Finish up by moving everything to the right place

  # We don't write directly to /images/snapshots because it can be NFS mounted
  # I'm not sure if it's longhorn or the NFS settings, but something
  # is causing write errors when reading and writing to it through
  # libguestfs. So instead we read/write on the tmpdir and then
  # move everything over to /images afterwards.

  info "Moving UEFI disk, squashfs root, and unified kernel image EFI to shared volume"

  mv /workspace/disk.raw "$uefidir/$__arch.raw.tmp"
  mv /workspace/root.img "$pxedir/root.img.tmp"
  mv /workspace/vmlinuz.efi "$pxedir/vmlinuz.efi.tmp"

  mv "$uefidir/$__arch.raw.tmp" "$uefidir/$__arch.raw"
  mv "$pxedir/root.img.tmp" "$pxedir/root.img"
  mv "$pxedir/vmlinuz.efi.tmp" "$pxedir/vmlinuz.efi"
}


main "$@"
