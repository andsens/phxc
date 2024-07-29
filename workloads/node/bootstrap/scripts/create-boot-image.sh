#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"

  declare -A artifacts
  declare -A digests

  mkdir -p /workspace/root

  info "Extracting container export"
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "/images/$VARIANT.new/node.tar" manifest.json)); do
    tar -xOf "/images/$VARIANT.new/node.tar" "$layer" | tar -xz -C /workspace/root
  done
  # During bootstrapping with kaniko these file can't be removed/overwritten,
  # instead we do it when creating the image
  rm /workspace/root/etc/hostname /workspace/root/etc/resolv.conf
  cp /assets/etc-hosts /workspace/root/etc/hosts
  ln -sf ../run/systemd/resolve/stub-resolv.conf /workspace/root/etc/resolv.conf
  # Revert the disabling of initramfs creation
  cp /assets/etc-initramfs-tools-update-initramfs.conf /workspace/root/etc/initramfs-tools/update-initramfs.conf

  local kernver
  kernver=$(readlink /workspace/root/vmlinuz)
  kernver=${kernver#'boot/vmlinuz-'}

  #######################
  ### Create root.img ###
  #######################

  info "Creating squashfs image"
  # Move boot dir out of the way before creating squashfs image
  mv /workspace/root/boot /workspace/boot
  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs /workspace/root /workspace/root.img -noappend -quiet $noprogress
  # Move boot dir back into place
  mv /workspace/boot /workspace/root/boot

  # Hash the root image so we can verify it during boot
  local rootimg_checksum
  rootimg_checksum=$(sha256sum /workspace/root.img | cut -d ' ' -f1)

  artifacts[/workspace/root.img]=/images/$VARIANT.new/root.img

  ####################
  ### Build initrd ###
  ####################

  info "Building initrd"
  chroot /workspace/root update-initramfs -c -k "$kernver"
  # See corresponding file in assets for explanation
  rm -f /workspace/root/usr/bin/ischroot

  mv "/workspace/root/$(readlink /workspace/root/vmlinuz)" /workspace/root/boot/vmlinuz
  mv "/workspace/root/$(readlink /workspace/root/initrd.img)" /workspace/root/boot/initrd
  # Remove kernel symlinks
  rm /workspace/root/initrd.img* /workspace/root/vmlinuz*
  # ...and the initramfs copy that a rpi hook creates
  [[ $VARIANT != rpi ]] || rm -f /workspace/root/boot/firmware/initramfs*

  artifacts[/workspace/root/boot/vmlinuz]=/images/$VARIANT.new/vmlinuz
  artifacts[/workspace/root/boot/initrd]=/images/$VARIANT.new/initrd

  ############################
  ### Unified kernel image ###
  ############################

  # Raspberry PI does not implement UEFI, so skip building a UKI
  if [[ $VARIANT != rpi ]]; then

    info "Creating unified kernel image"
    chroot /workspace/root /lib/systemd/ukify build \
      --uname="$kernver" \
      --linux=boot/vmlinuz \
      --initrd=boot/initrd \
      --cmdline="root=/run/initramfs/root.img root_sha256=$rootimg_checksum noresume" \
      --output=/boot/uki.efi

    local uki_size_b
    uki_size_b=$(stat -c %s /workspace/root/boot/uki.efi)
    (( uki_size_b <= 1024 * 1024 * 64 )) || \
      warning "uki.efi size exceeds 64MiB. Transferring the image via TFTP will result in its truncation"

    artifacts[/workspace/root/boot/uki.efi]=/images/$VARIANT.new/uki.efi

    # Extract digests used for PE signatures so we can use them for remote attestation
    digests[uki]=$(/signify/bin/python3 /scripts/get-pe-digest.py --json /workspace/root/boot/uki.efi)
    # See https://lists.freedesktop.org/archives/systemd-devel/2022-December/048694.html
    # as to why we also measure the embedded kernel
    objcopy -O binary --only-section=.linux /workspace/root/boot/uki.efi /workspace/uki-kernel
    digests[kernel]=$(/signify/bin/python3 /scripts/get-pe-digest.py --json /workspace/uki-kernel)
  fi

  ######################
  ### Build boot.img ###
  ######################

  if [[ $VARIANT = rpi ]]; then

    printf "console=ttyS0,115200 console=tty0 root=/run/initramfs/root.img root_sha256=%s noresume" "$rootimg_checksum" > /workspace/cmdline.txt

    local file_size fs_table_size_b firmware_size_b=0
    fs_table_size_b=$(( 1024 * 1024 )) # Total guess, but should be enough
    while IFS= read -d $'\n' -r file_size; do
      firmware_size_b=$(( firmware_size_b + file_size ))
    done < <(find /workspace/root/boot/firmware -type f -exec stat -c %s \{\} \;)
    disk_size_kib=$((
      (
        fs_table_size_b +
        $(stat -c %s /assets/config.txt) +
        $(stat -c %s /workspace/cmdline.txt) +
        $(stat -c %s /workspace/root/boot/vmlinuz) +
        $(stat -c %s /workspace/root/boot/initrd) +
        firmware_size_b +
        (1024 * 1024) +
        1023
      ) / 1024
    ))

    # https://github.com/raspberrypi/rpi-eeprom/issues/375
    # This is more of a TFTP limitation than anything else
    (( disk_size_kib <= 1024 * 64 )) || \
      warning "boot.img size exceeds 64MiB (%dMiB). Transferring the image via TFTP will result in its truncation" "$((disk_size_kib / 1024))"

    guestfish -xN /workspace/boot.img=disk:${disk_size_kib}K -- <<EOF
mkfs fat /dev/sda
mount /dev/sda /

copy-in /assets/config.txt /
copy-in /workspace/cmdline.txt /
copy-in /workspace/root/boot/vmlinuz /
mv /vmlinuz /vmlinuz.gz
copy-in /workspace/root/boot/initrd /
mv /initrd /initrd.cpio.zst
copy-in /workspace/root/boot/firmware /
glob mv /firmware/* /
rm-rf /firmware
EOF

    artifacts[/workspace/boot.img]=/images/$VARIANT.new/boot.img

  fi

  ######################
  ### Build node.raw ###
  ######################

  if [[ $VARIANT != rpi ]]; then

    local efisuffix
    case $VARIANT in
      amd64) efisuffix=x64 ;;
      arm64) efisuffix=aa64 ;;
      default) fatal "Unknown variant: %s" "$VARIANT" ;;
    esac

    info "Generating node settings"
    mkdir /workspace/node-settings
    local file node_settings_size_b=0
    for file in /node-settings/*; do
      node_settings_size_b=$(( node_settings_size_b + $(stat -c %s "$file") ))
      cp "$file" "/workspace/node-settings/$(basename "$file" | sed s/:/-/g)"
    done

    local sector_size_b=512 gpt_size_b partition_offset_b partition_size_b disk_size_kib
    gpt_size_b=$((33 * sector_size_b))
    partition_offset_b=$((1024 * 1024))
    # efi * 2 : The EFI boot loader is copied to two different destinations
    # stat -c %s : Size in bytes of the file
    # ... (sector_size_b - 1) ) / sector_size_b * sector_size_b : Round to next sector
    partition_size_b=$((
      (
        fs_table_size_b +
        node_settings_size_b +
        $(stat -c %s /workspace/root/boot/uki.efi) +
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

    guestfish -xN /workspace/node.raw=disk:${disk_size_kib}K -- <<EOF
part-init /dev/sda gpt
part-add /dev/sda primary $(( partition_offset_b / sector_size_b )) $(( (partition_offset_b + partition_size_b ) / sector_size_b - 1 ))
part-set-bootable /dev/sda 1 true
part-set-disk-guid /dev/sda $DISK_UUID
part-set-gpt-guid /dev/sda 1 $ESP_UUID

mkfs vfat /dev/sda1
mount /dev/sda1 /

mkdir-p /EFI/BOOT
copy-in /workspace/root/boot/uki.efi /EFI/BOOT/
mv /EFI/BOOT/uki.efi /EFI/BOOT/BOOT${efisuffix^^}.EFI

mkdir-p /home-cluster
copy-in /workspace/root.img /home-cluster/
copy-in /workspace/node-settings /home-cluster/
EOF

    artifacts[/workspace/node.raw]=/images/$VARIANT.new/node.raw

  fi

  ################################
  ### Generate/extract digests ###
  ################################

  local digest_key digests_doc={}
  for digest_key in "${!digests[@]}"; do
    digests_doc=$(jq --arg digest_key "$digest_key" --argjson digests "${digests[$digest_key]}" '
      .[$digest_key] = $digests' <<<"$digests_doc"
    )
  done
  printf "%s\n" "$digests_doc" >/workspace/digests.json

  artifacts[/workspace/digests.json]=/images/$VARIANT.new/digests.json

  ################
  ### Finalize ###
  ################

  # Finish up by moving everything to the right place in the most atomic way possible
  # as to avoid leaving anything in an incomplete state

  info "Moving UEFI disk, squashfs root, shim bootloader, mok manager, and unified kernel image EFI to shared volume"

  # Move all artifacts into the /images mount
  local src
  for src in "${!artifacts[@]}"; do
    mv "$src" "${artifacts[$src]}"
  done

  # Move current node image to old, move new images from tmp to current
  if [[ -e /images/$VARIANT ]]; then
    rm -rf "/images/$VARIANT.old"
    mv "/images/$VARIANT" "/images/$VARIANT.old"
  fi
  mv "/images/$VARIANT.new" "/images/$VARIANT"

  [[ -z "$CHOWN" ]] || chown -R "$CHOWN" "/images/$VARIANT"
}

main "$@"
