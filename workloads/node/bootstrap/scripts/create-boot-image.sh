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
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "/workspace/artifacts/node.tar" manifest.json)); do
    tar -xOf "/workspace/artifacts/node.tar" "$layer" | tar -xz -C /workspace/root
  done
  # During bootstrapping with kaniko these files can't be removed/overwritten,
  # instead we do it when creating the image
  rm /workspace/root/etc/hostname /workspace/root/etc/resolv.conf
  ln -sf ../run/systemd/resolve/stub-resolv.conf /workspace/root/etc/resolv.conf
  mv /workspace/root/etc/hosts.tmp /workspace/root/etc/hosts
  mv /workspace/root/etc/fstab.tmp /workspace/root/etc/fstab

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

  artifacts[/workspace/root.img]=root.${sha256sums[root.img]}.img
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
  artifacts[/workspace/root/boot/initrd.img]=initrd.img

  ######################
  ### Build boot.img ###
  ######################

  if [[ $VARIANT = rpi* ]]; then

    info "Building RaspberryPI boot.img"

    case $VARIANT in
      rpi5)
        mv /workspace/root/boot/vmlinuz /workspace/root/boot/firmware/kernel_2712.img
        mv /workspace/root/boot/initrd.img /workspace/root/boot/firmware/initramfs_2712
        unset 'artifacts[/workspace/root/boot/initrd.img]'
        artifacts[/workspace/root/boot/firmware/initramfs_2712]=initrd.img
        ;;
      rpi4)
        mv /workspace/root/boot/vmlinuz /workspace/root/boot/firmware/kernel8.img
        mv /workspace/root/boot/initrd.img /workspace/root/boot/firmware/initramfs8
        unset 'artifacts[/workspace/root/boot/initrd.img]'
        artifacts[/workspace/root/boot/firmware/initramfs8]=initrd.img
        ;;
      rpi3)
        mv /workspace/root/boot/vmlinuz /workspace/root/boot/firmware/kernel7.img
        mv /workspace/root/boot/initrd.img /workspace/root/boot/firmware/initramfs7
        unset 'artifacts[/workspace/root/boot/initrd.img]'
        artifacts[/workspace/root/boot/firmware/initramfs7]=initrd.img
        ;;
      default)
        ;;
    esac

    # The last "console=" wins with respect to initramfs stdout/stderr output
    printf "console=ttyS0,115200 console=tty0 %s" "$kernel_cmdline" > /workspace/cmdline.txt

    # Adjust config.txt for being embedded in boot.img
    sed 's/boot_ramdisk=1/auto_initramfs=1/' <"/assets/config-${VARIANT}.txt" >/workspace/config.txt
    cp "/assets/config-${VARIANT}.txt" /workspace/config-netboot.txt
    artifacts[/workspace/config-netboot.txt]=config.txt

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
    ! $DEBUG || export LIBGUESTFS_TRACE=1 LIBGUESTFS_DEBUG=1
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
    artifacts[/workspace/boot.img]=boot.img

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

    artifacts[/boot/pcr11.json]=pcr11.json

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

    artifacts[/workspace/root/boot/uki.efi]=uki.efi

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
    digests=$(jq --arg key "$key" --argjson authentihashes "${authentihashes[$key]}" \
      '.authentihashes[$key] = $authentihashes' <<<"$digests"
    )
  done
  printf "%s\n" "$digests" >/workspace/digests.json

  artifacts[/workspace/digests.json]=digests.json

  ################
  ### Finalize ###
  ################

  info "Assembling artifacts"
  local src mv_failed=0
  for src in "${!artifacts[@]}"; do
    mv "$src" "/workspace/artifacts/${artifacts[$src]}" || mv_failed=$?
  done
  [[ $mv_failed -eq 0 ]] || return $mv_failed

  info "Uploading artifacts to boot-server"
  local jwt_token url_path=images/$VARIANT retry=15
  while true; do
    jwt_token=$(step crypto jwt sign --key /secureboot/tls.key --iss bootstrap --jti '' \
      --aud boot-server --sub "PUT $url_path" --nbf "$(date -d'-30sec' +%s)" --exp "$(date -d'+30sec' +%s)")
    if ! curl --cacert /workspace/root_ca.crt \
        -H "Authorization: Bearer $jwt_token" \
        -fL --no-progress-meter --connect-timeout 5 \
        -XPUT -F image=@<(cd /workspace/artifacts; tar -c -- "${artifacts[@]}") \
        "https://boot-server.node.svc.cluster.local:8020/$url_path" >/dev/null; then
      error "Failed to upload image, retrying in %ds" $retry
      sleep $retry
      continue
    fi
    break
  done
}

main "$@"
