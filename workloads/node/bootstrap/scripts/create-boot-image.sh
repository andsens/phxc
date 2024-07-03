#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"
  # shellcheck disable=SC2154

  mkdir -p /workspace/root

  info "Extracting container export"
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "/images/$ARCH/node.new.tar" manifest.json)); do
    tar -xOf "/images/$ARCH/node.new.tar" "$layer" | tar -xz -C /workspace/root
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
  local shimsuffix
  case $ARCH in
    amd64) shimsuffix=x64 ;;
    aa64) shimsuffix=arm64 ;;
    default) fatal "Unknown processor architecture: %s" "$ARCH" ;;
  esac

  guestfish -xN /workspace/node.raw=disk:${disk_size_kib}K -- <<EOF
part-init /dev/sda gpt
part-add /dev/sda primary $(( partition_offset_b / sector_size_b )) $(( (partition_offset_b + partition_size_b ) / sector_size_b - 1 ))
part-set-bootable /dev/sda 1 true
part-set-disk-guid /dev/sda $DISK_UUID
part-set-gpt-guid /dev/sda 1 $ESP_UUID

mkfs vfat /dev/sda1
mount /dev/sda1 /

mkdir-p /EFI/BOOT
copy-in /usr/lib/shim/shim${shimsuffix}.efi.signed /EFI/BOOT/
mv /EFI/BOOT/shim${shimsuffix}.efi.signed /EFI/BOOT/BOOT${shimsuffix^^}.EFI
copy-in /usr/lib/shim/mm${shimsuffix}.efi.signed /EFI/BOOT/
mv /EFI/BOOT/mm${shimsuffix}.efi.signed /EFI/BOOT/mm${shimsuffix}.efi
copy-in /workspace/vmlinuz.efi /EFI/BOOT/
mv /EFI/BOOT/vmlinuz.efi /EFI/BOOT/grub${shimsuffix}.efi

mkdir-p /home-cluster
copy-in /workspace/root/etc/home-cluster/secureboot.der /home-cluster/
copy-in /workspace/root.img /home-cluster/
copy-in /workspace/node-settings /home-cluster/
EOF

  # Finish up by moving everything to the right place in the most atomic way possible
  # as to avoid leaving anything in an incomplete state

  info "Moving UEFI disk, squashfs root, shim bootloader, mok manager, and unified kernel image EFI to shared volume"

  # Extract digests used for PE signatures so we can use them for remote attestation
  /signify/bin/python3 /scripts/get-pe-digest.py --json /workspace/vmlinuz.efi >/workspace/vmlinuz.efi.digest.json
  /signify/bin/python3 /scripts/get-pe-digest.py --json /usr/lib/shim/shim${shimsuffix}.efi.signed >/workspace/shim.efi.digest.json

  local \
    tmpdir=/images/$ARCH.tmp \
    olddir=/images/$ARCH.old \
       dir=/images/$ARCH

  rm -rf "$tmpdir"
  mkdir "/images/$ARCH.tmp"
  mv "$dir/node.new.tar"                        "$tmpdir/node.tar"
  cp /usr/lib/shim/shim${shimsuffix}.efi.signed "$tmpdir/shim.efi"
  mv /workspace/shim.efi.digest.json            "$tmpdir/shim.efi.digest.json"
  cp /usr/lib/shim/mm${shimsuffix}.efi.signed   "$tmpdir/mm.efi"
  mv /workspace/root.img                        "$tmpdir/root.img"
  mv /workspace/vmlinuz.efi                     "$tmpdir/vmlinuz.efi"
  mv /workspace/vmlinuz.efi.digest.json         "$tmpdir/vmlinuz.efi.digest.json"
  mv /workspace/node.raw                        "$tmpdir/node.raw"

  rm -rf "$olddir"
  mv "$dir" "$olddir"
  mv "$tmpdir" "$dir"
  [[ -z "$CHOWN" ]] || chown -R "$CHOWN" "$dir"
}

main "$@"