#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

export EFI_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8

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
  # When bootstrapping outside kubernetes kaniko includes /workspace in the snapshot for some reason, remove it here
  rm -rf /workspace/root/workspace

  local kernver
  kernver=$(echo /workspace/root/lib/modules/*)
  kernver=${kernver#'/workspace/root/lib/modules/'}

  #######################
  ### Create root.img ###
  #######################

  info "Creating squashfs image"

  # Move boot dir to workspace before creating squashfs image
  mv /workspace/root/boot /workspace/boot

  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs /workspace/root /workspace/root.img -noappend -quiet -comp zstd $noprogress

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
    cpio -id </workspace/boot/initramfs.img
  )
  cp /workspace/initramfs/etc/fstab /workspace/envsubst.tmp
  # shellcheck disable=SC2016
  ROOT_SHA256=${sha256sums[root.img]} envsubst '${ROOT_SHA256}' </workspace/envsubst.tmp >/workspace/initramfs/etc/fstab

  local share_phxc=/workspace/initramfs/usr/share/phxc
  mkdir "$share_phxc"
  printf '%s  /efi/phxc/root.%s.img' "${sha256sums[root.img]}" "${sha256sums[root.img]}" >"$share_phxc/root.img.sha256.checksum"
  printf '%s' "${sha256sums[root.img]}" >"$share_phxc/root.img.sha256"
  (
    cd /workspace/initramfs
    find . -print0 | cpio -o --null --format=newc 2>/dev/null | zstd -15 >/workspace/boot/initramfs.img
  )
  ! $DEBUG || artifacts[initramfs.img]=/workspace/boot/initramfs.img

  local kernel_cmdline=()
  ! $DEBUG || kernel_cmdline+=("rd.shell")
  # ! $DEBUG || kernel_cmdline+=("rd.break")

  ############################
  ### RaspberryPI boot.img ###
  ############################

  if [[ $VARIANT = rpi* ]]; then

    info "Building RaspberryPI boot.img"

    declare -A boot_img_files

    case $VARIANT in
      rpi5)
        boot_img_files[initramfs_2712]=/workspace/boot/initramfs.img
        boot_img_files[kernel_2712.img]=/workspace/boot/vmlinuz
        ;;
      rpi4)
        boot_img_files[kernel8]=/workspace/boot/initramfs.img
        boot_img_files[initramfs8.img]=/workspace/boot/vmlinuz
        ;;
      rpi3)
        boot_img_files[kernel7]=/workspace/boot/initramfs.img
        boot_img_files[initramfs7.img]=/workspace/boot/vmlinuz
        ;;
      *) printf "Unknown rpi* variant: %s\n" "$VARIANT" >&2; return 1 ;;
    esac

    while IFS= read -r -d $'\0' filepath; do
      boot_img_files["${filepath#'/workspace/boot/firmware/'}"]=$filepath
    done < <(find /workspace/boot/firmware -print0)

    kernel_cmdline=(
      # The last "console=" wins with respect to initramfs stdout/stderr output
      "console=ttyS0,115200" console=tty0
      "${kernel_cmdline[@]}"
    )
    printf "%s " "${kernel_cmdline[@]}" > /workspace/cmdline.txt
    boot_img_files[cmdline.txt]=/workspace/cmdline.txt

    boot_files[config.txt]=/assets/config-${VARIANT}.txt

    # TODO: Adjust config.txt for being embedded in boot.img
    boot_img_files[config.txt]=/assets/config-${VARIANT}.txt

    local src dest tar_mode=-c
    for dest in "${!boot_img_files[@]}"; do
      src=${boot_img_files[$dest]}
      tar ${tar_mode}f /workspace/boot-img-files.tar \
        --transform="s#${src#/}#${dest#/}#" \
        "$src"
      tar_mode=-r
    done

    local disk_size_kib fs_table_size_b boot_img_files_size_b
    fs_table_size_b=$(( 1024 * 1024 )) # Total guess, but should be enough
    boot_img_files_size_b=$(( $(stat -c%s /workspace/boot-img-files.tar) + ( 1024 * 1024 ) ))
    disk_size_kib=$((
      (
        fs_table_size_b +
        boot_img_files_size_b +
        (1024 * 1024) +
        1023
      ) / 1024
    ))

    guestfish -xN /workspace/boot.img=disk:${disk_size_kib}K -- <<EOF
mkfs fat /dev/sda
mount /dev/sda /
tar-in /workspace/boot-img-files.tar /
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

    # Instead of installing systemd-boot-efi in the rather static create-boot-image image
    # Use the efi stub from the regularly updated actual image we are creating
    mkdir -p /usr/lib/systemd/boot
    ln -s /workspace/boot/systemd-boot-efi /usr/lib/systemd/boot/efi

    local uki_empty_pw_path=/workspace/boot/uki.diskenc-empty-pw.efi
    /lib/systemd/ukify build \
      --uname="$kernver" \
      --linux=/workspace/boot/vmlinuz \
      --initrd=/workspace/boot/initramfs.img \
      --cmdline="$(printf "%s " "${kernel_cmdline[@]}" "phxc.diskenc-allow-empty-pw")" \
      --output=$uki_empty_pw_path
    boot_files[/EFI/BOOT/BOOT${efi_arch}.EFI]=$uki_empty_pw_path
    artifacts[uki.diskenc-empty-pw.efi]=$uki_empty_pw_path
    sha256sums[uki.diskenc-empty-pw.efi]=$(sha256sum $uki_empty_pw_path | cut -d ' ' -f1)

    local \
      secureboot_key=/workspace/secureboot/tls.key secureboot_crt=/workspace/secureboot/tls.crt \
      uki_tpm2_path=/workspace/boot/uki.tpm2-diskenc.efi uki_secure_opts=()
    # Sign UKI if secureboot key & cert are present
    if [[ -e $secureboot_key && -e $secureboot_crt ]]; then
      uki_secure_opts+=("--secureboot-private-key=$secureboot_key" "--secureboot-certificate=$secureboot_crt")
      openssl x509 -in $secureboot_crt -outform der -out /workspace/secureboot.der
      boot_files[/phxc/secureboot.der]=/workspace/secureboot.der
    fi
    /lib/systemd/ukify build "${uki_secure_opts[@]}" \
      --uname="$kernver" \
      --linux=/workspace/boot/vmlinuz \
      --initrd=/workspace/boot/initramfs.img \
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
    boot_partition_size_b=$(( $(stat -c%s /workspace/boot-files.tar) + ( 1024 * 1024 * 5) )) \
    boot_sector_start boot_sector_end \
    disk_size_kib
  gpt_size_b=$((33 * sector_size_b))
  boot_sector_start=$(( partition_offset_b / sector_size_b ))
  boot_sector_end=$(( boot_sector_start + ( boot_partition_size_b / sector_size_b ) - 1 ))
  disk_size_kib=$((
    (
      partition_offset_b +
      boot_partition_size_b +
      gpt_size_b +
      1023
    ) / 1024
  ))

  ! $DEBUG || export LIBGUESTFS_TRACE=1 # LIBGUESTFS_DEBUG=1

  mkdir /usr/lib/modules # supermin bug workaround: https://lists.libguestfs.org/archives/list/guestfs@lists.libguestfs.org/thread/XVZXSSFUA5AISDPJKOI35CQB6LFUBXMU/
  # Use the kernel already installed in the image to launch supermin
  export \
    SUPERMIN_KERNEL=/workspace/boot/vmlinuz \
    SUPERMIN_KERNEL_VERSION=$kernver \
    SUPERMIN_MODULES=/workspace/root/usr/lib/modules/$kernver

  guestfish -xN /workspace/disk.img=disk:${disk_size_kib}K -- <<EOF
part-init /dev/sda gpt
part-add /dev/sda primary $boot_sector_start $boot_sector_end
part-set-bootable /dev/sda 1 true
part-set-gpt-guid /dev/sda 1 $EFI_UUID

mkfs vfat /dev/sda1
mount /dev/sda1 /
set-verbose false
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
