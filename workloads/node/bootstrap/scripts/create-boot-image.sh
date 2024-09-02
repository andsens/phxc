#!/usr/bin/env bash
# shellcheck source-path=../../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"

  declare -A artifacts
  declare -A authentihashes
  declare -A sha256sums

  mkdir -p /workspace/root

  info "Extracting container export"
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "/images/$VARIANT.new/node.tar" manifest.json)); do
    tar -xOf "/images/$VARIANT.new/node.tar" "$layer" | tar -xz -C /workspace/root
  done
  # During bootstrapping with kaniko these files can't be removed/overwritten,
  # instead we do it when creating the image
  rm /workspace/root/etc/hostname /workspace/root/etc/resolv.conf
  ln -sf ../run/systemd/resolve/stub-resolv.conf /workspace/root/etc/resolv.conf
  mv /workspace/root/etc/hosts.tmp /workspace/root/etc/hosts

  #######################
  ### Create root.img ###
  #######################

  info "Creating squashfs image"

  # Move boot dir out of the way before creating squashfs image, but keep the mountpoint itself
  mv /workspace/root/boot /workspace/boot
  mkdir /workspace/root/boot

  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs /workspace/root /workspace/root.img -noappend -quiet $noprogress

  # Move boot dir back into place
  rm -rf /workspace/root/boot
  mv /workspace/boot /workspace/root/boot

  # Hash the root image so we can verify it during boot
  sha256sums[root.img]=$(sha256sum /workspace/root.img | cut -d ' ' -f1)

  artifacts[/workspace/root.img]=/images/$VARIANT.new/root.${sha256sums[root.img]}.img
  local kernel_cmdline="rd.neednet=1 rootovl"
  ! $DEBUG || kernel_cmdline+=" rd.shell"

  #########################################
  ### Inject SHA-256 sum into initramfs ###
  #########################################

  info "Injecting SHA-256 of rootimg into initramfs"

  mkdir /workspace/initramfs
  (
    cd /workspace/initramfs
    zstd -cd /workspace/root/boot/initrd.img | cpio -id
  )
  cat <<EOF >/workspace/initramfs/etc/systemd/system.conf.d/rootimg.conf
[Manager]
DefaultEnvironment=ROOT_SHA256=${sha256sums[root.img]}
EOF
  (
    cd /workspace/initramfs
    find . -print0 | cpio -o --null --format=newc 2>/dev/null | zstd -19 >/workspace/root/boot/initrd.img
  )
  artifacts[/workspace/root/boot/initrd.img]=/images/$VARIANT.new/initrd.img

  ######################
  ### Build boot.img ###
  ######################

  if [[ $VARIANT = rpi* ]]; then

    info "Building RaspberryPI boot.img"

    # The last "console=" wins with respect to initramfs stdout/stderr output
    printf "console=ttyS0,115200 console=tty0 %s" "$kernel_cmdline" > /workspace/cmdline.txt

    # Adjust config.txt for being embedded in boot.img
    sed 's/boot_ramdisk=1/auto_initramfs=1/' <"/assets/config-${VARIANT}.txt" >/workspace/config.txt
    cp "/assets/config-${VARIANT}.txt" /workspace/config-netboot.txt
    artifacts[/workspace/config-netboot.txt]=/images/$VARIANT.new/config.txt

    local file_size fs_table_size_b firmware_size_b=0
    fs_table_size_b=$(( 1024 * 1024 )) # Total guess, but should be enough
    while IFS= read -d $'\n' -r file_size; do
      firmware_size_b=$(( firmware_size_b + file_size ))
    done < <(find /workspace/root/boot/firmware -type f -exec stat -c %s \{\} \;)
    disk_size_kib=$((
      (
        fs_table_size_b +
        $(stat -c %s "/assets/config-${VARIANT}.txt") +
        $(stat -c %s /workspace/cmdline.txt) +
        firmware_size_b +
        (1024 * 1024) +
        1023
      ) / 1024
    ))

    (( disk_size_kib <= 1024 * 64 )) || \
      warning "boot.img size exceeds 64MiB (%dMiB). Transferring the image via TFTP will result in its truncation" "$((disk_size_kib / 1024))"

    guestfish -xN /workspace/boot.img=disk:${disk_size_kib}K -- <<EOF
mkfs fat /dev/sda
mount /dev/sda /

copy-in /workspace/config.txt /
copy-in /workspace/cmdline.txt /
copy-in /workspace/root/boot/firmware /
glob mv /firmware/* /
rm-rf /firmware
EOF

    sha256sums[boot.img]=$(sha256sum /workspace/boot.img | cut -d ' ' -f1)
    artifacts[/workspace/boot.img]=/images/$VARIANT.new/boot.img

  fi

  ############################
  ### Unified kernel image ###
  ############################

  # Raspberry PI does not implement UEFI, so skip building a UKI
  if [[ $VARIANT != rpi* ]]; then

    info "Creating unified kernel image"

    printf "%s" "$kernel_cmdline" > /workspace/root/boot/cmdline.txt

    local kernver
    kernver=$(echo /workspace/root/lib/modules/*)
    kernver=${kernver#'/workspace/root/lib/modules/'}

    chroot /workspace/root /lib/systemd/systemd-measure calculate \
      --linux=boot/vmlinuz \
      --initrd=boot/initrd.img \
      --cmdline=boot/cmdline.txt \
      --osrel=/etc/os-release \
      --json=pretty \
      >/boot/pcr11.json

    artifacts[/boot/pcr11.json]=/images/$VARIANT.new/pcr11.json

    cp -r /secureboot /workspace/root/secureboot
    chroot /workspace/root /lib/systemd/ukify build \
      --uname="$kernver" \
      --linux=boot/vmlinuz \
      --initrd=boot/initrd.img \
      --cmdline="$kernel_cmdline" \
      --signtool=sbsign \
      --secureboot-private-key=/secureboot/tls.key \
      --secureboot-certificate=/secureboot/tls.crt \
      --output=/boot/uki.efi

    artifacts[/workspace/root/boot/uki.efi]=/images/$VARIANT.new/uki.efi

    local uki_size_b
    uki_size_b=$(stat -c %s /workspace/root/boot/uki.efi)
    (( uki_size_b <= 1024 * 1024 * 64 )) || \
      warning "uki.efi size exceeds 64MiB (%dMiB). Transferring the image via TFTP will result in its truncation" "$((uki_size_b / 1024 / 1024))"


    # Extract authentihashes used for PE signatures so we can use them for remote attestation
    authentihashes[uki.efi]=$(/signify/bin/python3 /scripts/get-pe-digest.py --json /workspace/root/boot/uki.efi)
    sha256sums[uki.efi]=$(sha256sum /workspace/root/boot/uki.efi | cut -d ' ' -f1)
    # See https://lists.freedesktop.org/archives/systemd-devel/2022-December/048694.html
    # as to why we also measure the embedded kernel
    objcopy -O binary --only-section=.linux /workspace/root/boot/uki.efi /workspace/uki-vmlinuz
    authentihashes[vmlinuz]=$(/signify/bin/python3 /scripts/get-pe-digest.py --json /workspace/uki-vmlinuz)
  fi

  ###########################
  ### Create digests.json ###
  ###########################

  local key digests='{"sha256sums": {}, "authentihashes": {}}'
  for key in "${!sha256sums[@]}"; do
    digests=$(jq --arg key "$key" --arg sha256sums "${sha256sums[$key]}" '
      .sha256sums[$key] = $sha256sums' <<<"$digests"
    )
  done
  for key in "${!authentihashes[@]}"; do
    digests=$(jq --arg key "$key" --argjson authentihashes "${authentihashes[$key]}" '
      .authentihashes[$key] = $authentihashes' <<<"$digests"
    )
  done
  printf "%s\n" "$digests" >/workspace/digests.json

  artifacts[/workspace/digests.json]=/images/$VARIANT.new/digests.json

  ################
  ### Finalize ###
  ################

  # Finish up by moving everything to the right place in the most atomic way possible
  # as to avoid leaving anything in an incomplete state

  info "Moving all assets to shared images/"

  # Move all artifacts into the /images mount
  local src mv_failed=0
  for src in "${!artifacts[@]}"; do
    mv "$src" "${artifacts[$src]}" || mv_failed=$?
  done
  [[ $mv_failed -eq 0 ]] || return $mv_failed

  # Move current node image to old, move new images from tmp to current
  if [[ -e /images/$VARIANT ]]; then
    rm -rf "/images/$VARIANT.old"
    mv "/images/$VARIANT" "/images/$VARIANT.old"
  fi
  mv "/images/$VARIANT.new" "/images/$VARIANT"

  [[ -z "$CHOWN" ]] || chown -R "$CHOWN" "/images/$VARIANT"
}

main "$@"
