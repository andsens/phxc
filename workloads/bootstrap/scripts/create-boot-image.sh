#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

export DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
export BOOT_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8
export LUKS_UUID=2a785738-5af5-4c13-88ae-e5f2d20e7049

main() {
  DOC="create-boot-image - Make an archived container image bootable
Usage:
  create-boot-image [options]

Options:
  --upload URL  Upload artifacts to the specified WebDAV server URL
  --chown UID   Change the owner & group UID of the artifacts to UID when done
"
# docopt parser below, refresh this parser with `docopt.sh create-boot-image.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:255};usage=${DOC:62:36}
digest=ec9f8;options=(' --upload 1' ' --chown 1');node_0(){ value __upload 0;}
node_1(){ value __chown 1;};node_2(){ optional 0 1;};cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:62:36}" >&2;exit 1;}'
local varnames=(__upload __chown) varname;for varname in "${varnames[@]}"; do
unset "var_$varname";done;parse 2 "$@";local p=${DOCOPT_PREFIX:-''};for \
varname in "${varnames[@]}"; do unset "$p$varname";done;eval $p'__upload=${var'\
'___upload:-};'$p'__chown=${var___chown:-};';local docopt_i=1;[[ $BASH_VERSION \
=~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in \
"${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' create-boot-image.sh`
  eval "$(docopt "$@")"

  source "$PKGROOT/.upkg/records.sh/records.sh"

  declare -A artifacts
  declare -A sha256sums
  declare -A boot_files
  ! $DEBUG || export LIBGUESTFS_TRACE=1
  # LIBGUESTFS_DEBUG=1

  #################################
  ### Extract container archive ###
  #################################

  info "Extracting container export"

  [[ -z $__chown ]] || chown "$__chown:$__chown" "/workspace/artifacts/node.tar"

  mkdir -p /workspace/root

  local filepath filename
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "/workspace/artifacts/node.tar" manifest.json)); do
    tar -xOf "/workspace/artifacts/node.tar" "$layer" | tar -xz -C /workspace/root
    # See https://github.com/opencontainers/image-spec/blob/5325ec48851022d6ded604199a3566254e72842a/layer.md#whiteouts
    while IFS= read -r -d $'\0' filepath; do
      filename=$(basename "$filepath")
      # shellcheck disable=SC2115
      rm -rf "$filepath" "$(dirname "$filepath")/${filename#'.wh.'}"
    done < <(find /workspace/root -name '.wh.*' -print0)
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
  mksquashfs /workspace/root /workspace/root.img -noappend -quiet -comp zstd $noprogress

  # Move boot dir back into place
  rm -rf /workspace/root/boot
  mv /workspace/boot /workspace/root/boot

  # Hash the root image so we can verify it during boot
  sha256sums[root.img]=$(sha256sum /workspace/root.img | cut -d ' ' -f1)

  artifacts[root.img]=/workspace/root.img
  boot_files["/phxc/root.${sha256sums[root.img]}.img"]=/workspace/root.img

  ##################################################
  ### Inject root.img SHA-256 sum into initramfs ###
  ##################################################

  info "Injecting SHA-256 of rootimg into initramfs"

  mkdir /workspace/initramfs
  (
    cd /workspace/initramfs
    zstd -cd /workspace/root/boot/initramfs.img | cpio -id
  )
  cat <<EOF >/workspace/initramfs/etc/systemd/system.conf.d/rootimg.conf
[Manager]
DefaultEnvironment=ROOT_SHA256=${sha256sums[root.img]}
EOF
  (
    cd /workspace/initramfs
    find . -print0 | cpio -o --null --format=newc 2>/dev/null | zstd -15 >/workspace/root/boot/initramfs.img
  )
  ! $DEBUG || artifacts[initramfs.img]=/workspace/root/boot/initramfs.img

  local kernel_cmdline=()
  ! $DEBUG || kernel_cmdline+=("rd.shell")
  # ! $DEBUG || kernel_cmdline+=("rd.break")

  ############################
  ### RaspberryPI boot.img ###
  ############################

  if [[ $VARIANT = rpi* ]]; then

    info "Building RaspberryPI boot.img"

    case $VARIANT in
      rpi5)
        mv /workspace/root/boot/vmlinuz /workspace/root/boot/firmware/kernel_2712.img
        mv /workspace/root/boot/initramfs.img /workspace/root/boot/firmware/initramfs_2712
        ! $DEBUG || artifacts[initramfs.img]=/workspace/root/boot/firmware/initramfs_2712
        ;;
      rpi4)
        mv /workspace/root/boot/vmlinuz /workspace/root/boot/firmware/kernel8.img
        mv /workspace/root/boot/initramfs.img /workspace/root/boot/firmware/initramfs8
        ! $DEBUG || artifacts[initramfs.img]=/workspace/root/boot/firmware/initramfs8
        ;;
      rpi3)
        mv /workspace/root/boot/vmlinuz /workspace/root/boot/firmware/kernel7.img
        mv /workspace/root/boot/initramfs.img /workspace/root/boot/firmware/initramfs7
        ! $DEBUG || artifacts[initramfs.img]=/workspace/root/boot/firmware/initramfs7
        ;;
      *) printf "Unknown rpi* variant: %s\n" "$VARIANT" >&2; return 1 ;;
    esac

    kernel_cmdline=(
      # The last "console=" wins with respect to initramfs stdout/stderr output
      "console=ttyS0,115200" console=tty0
      "${kernel_cmdline[@]}"
    )
    printf "%s " "${kernel_cmdline[@]}" > /workspace/cmdline.txt

    boot_files[config.txt]=/assets/config-${VARIANT}.txt

    # Adjust config.txt for being embedded in boot.img
    boot_files[config.txt]=/assets/config-${VARIANT}.txt

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
    artifacts[boot.img]=/workspace/boot.img
    boot_files[/boot.img]=/workspace/boot.img
  fi

  ############################
  ### Unified kernel image ###
  ############################

  # Raspberry PI does not implement UEFI, so skip building a UKI
  if [[ $VARIANT != rpi* ]]; then
    # Create (& optionally sign) unified kernel

    info "Creating unified kernel image"

    local efi_arch
    case "$VARIANT" in
      amd64) efi_arch=X64 ;;
      arm64) efi_arch=AA64 ;;
      *) fatal "Unknown variant: %s" "$VARIANT" ;;
    esac

    local kernver
    kernver=$(echo /workspace/root/lib/modules/*)
    kernver=${kernver#'/workspace/root/lib/modules/'}

    local uki_nopw_path=/workspace/root/boot/uki.nopw-diskenc.efi
    /lib/systemd/ukify build \
      --uname="$kernver" \
      --linux=/workspace/root/boot/vmlinuz \
      --initrd=/workspace/root/boot/initramfs.img \
      --cmdline="$(printf "%s " "${kernel_cmdline[@]}" "phxc.diskenc-nopw")" \
      --output=$uki_nopw_path
    boot_files[/EFI/BOOT/BOOT${efi_arch}.EFI]=$uki_nopw_path
    artifacts[uki.nopw-diskenc.efi]=$uki_nopw_path
    sha256sums[uki.nopw-diskenc.efi]=$(sha256sum $uki_nopw_path | cut -d ' ' -f1)

    local \
      secureboot_key=/workspace/secureboot/tls.key secureboot_crt=/workspace/secureboot/tls.crt \
      uki_tpm2_path=/workspace/root/boot/uki.tpm2-diskenc.efi uki_secure_opts=()
    # Sign UKI if secureboot key & cert are present
    if [[ -e $secureboot_key && -e $secureboot_crt ]]; then
      uki_secure_opts+=("--secureboot-private-key=$secureboot_key" "--secureboot-certificate=$secureboot_crt")
      openssl x509 -in $secureboot_crt -outform der -out /workspace/secureboot.der
      boot_files[/phxc/secureboot.der]=/workspace/secureboot.der
    fi
    /lib/systemd/ukify build "${uki_secure_opts[@]}" \
      --uname="$kernver" \
      --linux=/workspace/root/boot/vmlinuz \
      --initrd=/workspace/root/boot/initramfs.img \
      --cmdline="$(printf "%s " "${kernel_cmdline[@]}")" \
      --output=$uki_tpm2_path
    artifacts[uki.tpm2-diskenc.efi]=$uki_tpm2_path
    sha256sums[uki.tpm2-diskenc.efi]=$(sha256sum $uki_tpm2_path | cut -d ' ' -f1)
  fi

  #######################
  ### Create metadata ###
  #######################

  info "Creating image metadata file"

  local key meta
  meta=$(jq -n --arg variant "$VARIANT" --arg now "$(date --iso-8601=seconds --utc)" '{
    "variant": $variant,
    "build-date": $now,
    "sha256sums": {}
  }')
  for key in "${!sha256sums[@]}"; do
    meta=$(jq --arg key "$key" --arg sha256sums "${sha256sums[$key]}" '
      .sha256sums[$key] = $sha256sums' <<<"$meta"
    )
  done
  printf "%s\n" "$meta" >/workspace/meta.json

  artifacts[meta.json]=/workspace/meta.json

  ##################
  ### Disk image ###
  ##################

  info "Building disk image from artifacts"

  local src dest tar_mode=-c
  for dest in "${!boot_files[@]}"; do
    src=${boot_files[$dest]}
    tar ${tar_mode}f /workspace/boot-files.tar \
      --transform="s#${src#/}#${dest#/}#" \
      "$src"
    tar_mode=-r
  done
  local \
    sector_size_b=512 \
    gpt_size_b \
    partition_offset_b=$((1024 * 1024)) \
    boot_partition_size_b=$(( 1024 * 1024 * 1024 )) \
    data_partition_size_b=$(( 1024 * 1024 * 16 )) \
    boot_sector_start boot_sector_end \
    data_sector_start data_sector_end \
    disk_size_kib
  gpt_size_b=$((33 * sector_size_b))
  boot_sector_start=$(( partition_offset_b / sector_size_b ))
  boot_sector_end=$(( boot_sector_start + ( boot_partition_size_b / sector_size_b ) - 1 ))
  data_sector_start=$(( boot_sector_end + 1 ))
  data_sector_end=$(( data_sector_start + ( data_partition_size_b / sector_size_b ) - 1 ))
  disk_size_kib=$((
    (
      partition_offset_b +
      boot_partition_size_b +
      data_partition_size_b +
      gpt_size_b +
      1023
    ) / 1024
  ))
  guestfish -xN /workspace/disk.img=disk:${disk_size_kib}K -- <<EOF
part-init /dev/sda gpt
part-add /dev/sda primary $boot_sector_start $boot_sector_end
part-set-bootable /dev/sda 1 true
part-set-disk-guid /dev/sda $DISK_UUID
part-set-gpt-guid /dev/sda 1 $BOOT_UUID
part-add /dev/sda primary $data_sector_start $data_sector_end
part-set-gpt-guid /dev/sda 2 $DATA_UUID

mkfs vfat /dev/sda1
mount /dev/sda1 /

tar-in /workspace/boot-files.tar /
EOF
  artifacts[disk.img]=/workspace/disk.img

  #################
  ### Artifacts ###
  #################

  info "Archiving artifacts"

  local src dest
  for dest in "${!artifacts[@]}"; do
    src=${artifacts[$dest]}
    cp "$src" "/workspace/artifacts/$dest"
    [[ -z $__chown ]] || chown "$__chown:$__chown" "/workspace/artifacts/$dest"
  done
  $DEBUG || rm "/workspace/artifacts/node.tar"

  ##############
  ### Upload ###
  ##############

  # shellcheck disable=SC2154
  if [[ -n $__upload ]]; then

    info "Uploading artifacts to the image-registry"

    local upload_files=''
    for dest in "${!artifacts[@]}"; do
      upload_files="$upload_files,/workspace/artifacts/$dest"
    done
    curl_img_reg -DELETE "$__upload/$VARIANT.tmp/" || info "404 => No previous %s.tmp/ to delete" "$VARIANT"
    curl_img_reg --upload-file "{${upload_files#,}}" "$__upload/$VARIANT.tmp/"
    curl_img_reg -DELETE "$__upload/$VARIANT.old/" || info "404 => No previous %s.old/ to delete" "$VARIANT"
    curl_img_reg -XMOVE "$__upload/$VARIANT/" --header "Destination:$__upload/$VARIANT.old/" || info "404 => No previous %s/ to move to %s.old/" "$VARIANT" "$VARIANT"
    curl_img_reg -XMOVE "$__upload/$VARIANT.tmp/" --header "Destination:$__upload/${VARIANT}/"
  fi
}

curl_img_reg() {
  curl --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -fL --no-progress-meter --connect-timeout 5 \
    --retry 10 --retry-delay 60 \
    "$@"
}

main "$@"
