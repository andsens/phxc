#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
source "$PKGROOT/.upkg/records.sh/records.sh"

export ESP_PART_TYPE_UUID=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
# Microsoft basic data partition type GUID, used for rpi boot partition
export MSBDP_PART_TYPE_UUID=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7

export BOOT_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
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

  __upload=${__upload%'/'}

  declare -A artifacts
  local secureboot_key=/workspace/secureboot/tls.key \
        secureboot_crt=/workspace/secureboot/tls.crt
  if [[ -e $secureboot_key ]]; then
    info "Checking secureboot key"
    openssl rsa -in $secureboot_key -noout -check || fatal "Secureboot key must be a 2048 bit RSA key"
    [[ $(openssl rsa -in $secureboot_key -noout -text) =~ Private-Key:\ \(([0-9]+)\ bit, ]] || fatal "Unable to determine secureboot keysize"
    [[ ${BASH_REMATCH[1]} = 2048 ]] || fatal "Secureboot key must be a 2048 bit RSA key (got %d bit)" "${BASH_REMATCH[1]}"
  fi

  local image_types=(empty-pw) image_type
  if [[ $VARIANT = rpi* ]]; then
    image_types+=(rpi-otp)
  else
    image_types+=(tpm2)
  fi
  for image_type in "${image_types[@]}"; do
    mkdir -p "/workspace/boot-staging.$image_type/phxc"
  done

  #################################
  ### Extract container archive ###
  #################################

  info "Extracting container export"

  [[ -z $__chown ]] || chown "$__chown:$__chown" "/workspace/artifacts/node.tar"

  mkdir -p /workspace/root

  local filepath filename
  for layer in $(jq -r '.[0].Layers[]' <(tar -xOf "/workspace/artifacts/node.tar" manifest.json)); do
    tar -xOf "/workspace/artifacts/node.tar" "$layer" | tar -xzC /workspace/root
    # See https://github.com/opencontainers/image-spec/blob/5325ec48851022d6ded604199a3566254e72842a/layer.md#whiteouts
    while IFS= read -r -d $'\0' filepath; do
      filename=$(basename "$filepath")
      # shellcheck disable=SC2115
      rm -rf "$filepath" "$(dirname "$filepath")/${filename#'.wh.'}"
    done < <(find /workspace/root -name '.wh.*' -print0)
  done
  verbose "Adding post-build files to root filesystem"
  # During bootstrapping with kaniko these files can't be removed/overwritten,
  # instead we do it when creating the image
  rm /workspace/root/etc/hostname /workspace/root/etc/resolv.conf
  ln -sf ../run/systemd/resolve/stub-resolv.conf /workspace/root/etc/resolv.conf
  mv /workspace/root/etc/hosts.tmp /workspace/root/etc/hosts
  mv /workspace/root/etc/fstab.tmp /workspace/root/etc/fstab
  # When bootstrapping outside kubernetes, kaniko includes /workspace in the snapshot for some reason, remove it here
  rm -rf /workspace/root/workspace
  if [[ -e $secureboot_key ]]; then
    openssl rsa -in $secureboot_key -pubout >/workspace/root/usr/local/share/phxc/secureboot.pub
    if [[ -e $secureboot_crt ]]; then
      cp $secureboot_crt /workspace/root/usr/local/share/phxc/secureboot.crt
    fi
  fi

  # Move boot contents to workspace, it's not part of the root image
  mv /workspace/root/boot /workspace/boot
  # Leave mountpoint for boot partition
  mkdir /workspace/root/boot

  local kernver
  kernver=$(readlink /workspace/root/vmlinuz)
  kernver=${kernver#'boot/vmlinuz-'}
  mv "/workspace/boot/initrd.img-$kernver" /workspace/boot/initramfs.img
  mv "/workspace/boot/vmlinuz-$kernver" /workspace/boot/vmlinuz
  rm /workspace/root/vmlinuz \
     /workspace/root/vmlinuz.old
  rm -f /workspace/root/initrd.img \
        /workspace/root/initrd.img.old

  ################################
  ### Move /var out of the way ###
  ################################

  mv /workspace/root/var /workspace/root/usr/local/lib/phxc/var-template
  mkdir /workspace/root/var

  #######################
  ### Create root.img ###
  #######################

  info "Creating squashfs image"

  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs /workspace/root /workspace/root.img -noappend -quiet -comp zstd $noprogress

  # Hash the root image so we can verify it during boot
  local rootimg_sha256
  rootimg_sha256=$(sha256 /workspace/root.img)
  artifacts[root.img]=/workspace/root.img
  printf '%s\n' "$rootimg_sha256" >/workspace/root.img.sha256
  artifacts[root.img.sha256]=/workspace/root.img.sha256

  ##################################################
  ### Inject root.img SHA-256 sum into initramfs ###
  ##################################################

  info "Injecting image checksum into initramfs"

  mkdir /workspace/initramfs
  verbose "Decompressing initramfs"
  (
    cd /workspace/initramfs
    cpio -id </workspace/boot/initramfs.img
  )
  cp /workspace/initramfs/etc/fstab /workspace/envsubst.tmp
  # shellcheck disable=SC2016
  ROOTIMG_SHA256=$rootimg_sha256 envsubst '${ROOTIMG_SHA256}' </workspace/envsubst.tmp >/workspace/initramfs/etc/fstab

  local share_phxc=/workspace/initramfs/usr/share/phxc
  mkdir "$share_phxc"
  printf '%s  /boot/phxc/root.%s.img\n' "$rootimg_sha256" "$rootimg_sha256" >"$share_phxc/root.img.sha256sum"
  printf '%s\n' "$rootimg_sha256" >"$share_phxc/root.img.sha256"

  verbose "Compressing initramfs"
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

    kernel_cmdline=(
      # The last "console=" wins with respect to initramfs stdout/stderr output
      "console=ttyS0,115200" console=tty0
      "${kernel_cmdline[@]}"
      # See https://github.com/k3s-io/k3s-ansible/issues/179
      cgroup_enable=memory
    )

    for image_type in "${image_types[@]}"; do
      mkdir -p "/workspace/rpi-bootimg-staging.$image_type/phxc"
      verbose "Staging RPi firmware & configuration files (%s)" "$image_type"
      case $VARIANT in
        rpi2|rpi3)
          cp /workspace/boot/vmlinuz "/workspace/rpi-bootimg-staging.$image_type/kernel7.img"
          cp /workspace/boot/initramfs.img "/workspace/rpi-bootimg-staging.$image_type/initramfs7"
          ;;
        rpi4)
          cp /workspace/boot/vmlinuz "/workspace/rpi-bootimg-staging.$image_type/kernel8.img"
          cp /workspace/boot/initramfs.img "/workspace/rpi-bootimg-staging.$image_type/initramfs8"
          ;;
        rpi5)
          cp /workspace/boot/vmlinuz "/workspace/rpi-bootimg-staging.$image_type/kernel_2712.img"
          cp /workspace/boot/initramfs.img "/workspace/rpi-bootimg-staging.$image_type/initramfs_2712"
          ;;
        *) printf "Unknown rpi* variant: %s\n" "$VARIANT" >&2; return 1 ;;
      esac
      cp -r /workspace/boot/firmware/* "/workspace/rpi-bootimg-staging.$image_type"
      printf "%s " "${kernel_cmdline[@]}" >"/workspace/rpi-bootimg-staging.$image_type/cmdline.txt"
      cp "/workspace/boot/config-${VARIANT}-bootimg.txt" "/workspace/rpi-bootimg-staging.$image_type/config.txt"
      cp "/workspace/boot/config-${VARIANT}-bootimg.txt" "/workspace/rpi-bootimg-staging.$image_type/tryboot.txt"
      cp "/workspace/boot/config-${VARIANT}-boot.txt" "/workspace/boot-staging.$image_type/config.txt"
      cp "/workspace/boot/config-${VARIANT}-boot.txt" "/workspace/boot-staging.$image_type/tryboot.txt"
    done

    verbose "Calculating the required boot.img size"
    local block_size_b=512
    local bootimg_fat16_table_size_b=$(( 512 * 1024 )) bootimg_files_size_b
    bootimg_files_size_b=$(($(du -sB$block_size_b /workspace/rpi-bootimg-staging.empty-pw | cut -d$'\t' -f1) * block_size_b))
    # The extra 256 * block_size_b is wiggleroom for directories, signatures, and configs
    local disk_size_b=$((
      (
        bootimg_fat16_table_size_b +
        bootimg_files_size_b +
        256 * block_size_b +
        block_size_b - 1
      ) / block_size_b * block_size_b
    ))

    verbose "Creating boot.rpi-otp.img for disk encryption with RPi OTP"
    truncate -s"$disk_size_b" /workspace/boot-staging.rpi-otp/boot.img
    mkfs.vfat -n "RPI-RAMDISK" /workspace/boot-staging.rpi-otp/boot.img
    mcopy -sbQmi /workspace/boot-staging.rpi-otp/boot.img /workspace/rpi-bootimg-staging.rpi-otp/* ::/
    artifacts[boot.rpi-otp.img]=/workspace/boot-staging.rpi-otp/boot.img

    verbose "Creating boot.img signature file"
    printf "%s\nts: %d\n" "$(sha256 /workspace/boot-staging.rpi-otp/boot.img)" "$(date -u +%s)" \
      >/workspace/boot-staging.rpi-otp/boot.sig
    if [[ -e $secureboot_key ]]; then
      verbose "Adding boot.img signature to signature file"
      local bootimg_sig
      bootimg_sig=$(openssl dgst -sign $secureboot_key -sha256 /workspace/boot-staging.rpi-otp/boot.img | xxd -p -c0)
      printf "rsa2048: %s\n" "$bootimg_sig" >>/workspace/boot-staging.rpi-otp/boot.sig
    fi
    artifacts[boot.rpi-otp.sig]=/workspace/boot-staging.rpi-otp/boot.sig

    verbose "Creating boot.img for disk encryption with an empty password"
    printf "phxc.empty-pw" >>/workspace/rpi-bootimg-staging.empty-pw/cmdline.txt
    truncate -s"$disk_size_b" /workspace/boot-staging.empty-pw/boot.img
    mkfs.vfat -n "RPI-RAMDISK" /workspace/boot-staging.empty-pw/boot.img
    mcopy -sbQmi /workspace/boot-staging.empty-pw/boot.img /workspace/rpi-bootimg-staging.empty-pw/* ::/
    artifacts[boot.empty-pw.img]=/workspace/boot-staging.empty-pw/boot.img

    verbose "Creating boot.empty-pw.img signature file"
    printf "%s\nts: %d\n" "$(sha256 /workspace/boot-staging.empty-pw/boot.img)" "$(date -u +%s)" \
      >/workspace/boot-staging.empty-pw/boot.sig
    artifacts[boot.empty-pw.sig]=/workspace/boot-staging.empty-pw/boot.sig
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

    verbose "Creating uki.empty-pw.efi for disk encryption with an empty password"
    mkdir -p /workspace/boot-staging.empty-pw/EFI/BOOT
    /lib/systemd/ukify build \
      --uname="$kernver" \
      --linux=/workspace/boot/vmlinuz \
      --initrd=/workspace/boot/initramfs.img \
      --cmdline="$(printf "%s " "${kernel_cmdline[@]}" "phxc.empty-pw")" \
      --output=/workspace/boot-staging.empty-pw/EFI/BOOT/BOOT${efi_arch}.EFI
    artifacts[uki.empty-pw.efi]=/workspace/boot-staging.empty-pw/EFI/BOOT/BOOT${efi_arch}.EFI

    verbose "Creating uki.efi for disk encryption with TPM2"
    mkdir -p /workspace/boot-staging.tpm2/EFI/BOOT
    local uki_secure_opts=()
    # Sign UKI if secureboot key & cert are present
    if [[ -e $secureboot_key && -e $secureboot_crt ]]; then
      verbose "Adding secureboot signing parameters for uki.efi creation"
      uki_secure_opts+=("--secureboot-private-key=$secureboot_key" "--secureboot-certificate=$secureboot_crt")
      openssl x509 -in $secureboot_crt -outform der -out /workspace/boot-staging.tpm2/phxc/secureboot.der
    fi
    /lib/systemd/ukify build "${uki_secure_opts[@]}" \
      --uname="$kernver" \
      --linux=/workspace/boot/vmlinuz \
      --initrd=/workspace/boot/initramfs.img \
      --cmdline="$(printf "%s " "${kernel_cmdline[@]}")" \
      --output=/workspace/boot-staging.tpm2/EFI/BOOT/BOOT${efi_arch}.EFI
    artifacts[uki.tpm2.efi]=/workspace/boot-staging.tpm2/EFI/BOOT/BOOT${efi_arch}.EFI
  fi

  ##################
  ### Disk image ###
  ##################

  for image_type in "${image_types[@]}"; do
    info "Building disk image from artifacts (%s)" "$image_type"

    verbose "Calculating size of boot partition (%s)" "$image_type"
    local block_size_b=512
    local boot_files_size_b boot_reserved_b=$((1024 * 1024 * 4))
    boot_files_size_b=$(( (
        $(du -sB$block_size_b "/workspace/boot-staging.$image_type" | cut -d$'\t' -f1) +
        $(du -sB$block_size_b /workspace/root.img | cut -d$'\t' -f1)
      ) * block_size_b
    ))
    local boot_fat32_table_size_b=$(( (2 * ((boot_files_size_b + boot_reserved_b) / 1024 / 1024) + 20) * 1024 ))
    local boot_size_b=$((
      (
        boot_fat32_table_size_b +
        boot_files_size_b +
        boot_reserved_b +
        block_size_b - 1
      ) / block_size_b * block_size_b
    ))

    local boot_partition_name=EFI-SYSTEM
    [[ $VARIANT != rpi* ]] || boot_partition_name=RPI-BOOT

    verbose "Building boot partition (%s)" "$image_type"
    truncate -s"$boot_size_b" "/workspace/boot.$image_type.img"
    mkfs.vfat -n $boot_partition_name -F 32 "/workspace/boot.$image_type.img"
    mcopy -sbQmi "/workspace/boot.$image_type.img" "/workspace/boot-staging.$image_type"/* ::/
    mcopy -sbQmi "/workspace/boot.$image_type.img" /workspace/root.img "::/phxc/root.$rootimg_sha256.img"
    ! $DEBUG || artifacts[boot.$image_type.img]="/workspace/boot.$image_type.img"

    verbose "Calculating size of disk image (%s)" "$image_type"
    local gpt_size_b=$((33 * 512)) partition_offset_b=$((1024 * 1024))
    local disk_size_b=$((
      (
        partition_offset_b +
        boot_size_b +
        gpt_size_b +
        block_size_b - 1
      ) / block_size_b * block_size_b
    ))

    verbose "Building disk image (%s)" "$image_type"
    local partition_type=$ESP_PART_TYPE_UUID
    # Let boot partition on rpi be a normal partition for easier mounting on windows
    [[ $VARIANT != rpi* ]] || partition_type=$MSBDP_PART_TYPE_UUID
    truncate -s"$disk_size_b" "/workspace/disk.$image_type.img"
    sfdisk -q "/workspace/disk.$image_type.img" <<EOF
label: gpt
start=$(( partition_offset_b / block_size_b )) size=$(( boot_size_b / block_size_b )), type=$partition_type, bootable, uuid=$BOOT_UUID
EOF
    dd if="/workspace/boot.$image_type.img" of="/workspace/disk.$image_type.img" \
      bs=$block_size_b seek=$((partition_offset_b / block_size_b)) count=$((boot_size_b / block_size_b)) conv=notrunc

    artifacts[disk.$image_type.img]=/workspace/disk.$image_type.img
  done

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

    wait_for_unlock "$__upload/$VARIANT.tmp"
    keep_locked "$__upload/$VARIANT.tmp" & lock_pid=$!
    curl_imgreg -DELETE "$__upload/$VARIANT.tmp/" || info "404 => No previous %s.tmp/ to delete" "$VARIANT"

    local upload_files=''
    for dest in "${!artifacts[@]}"; do
      upload_files="$upload_files,/workspace/artifacts/$dest"
    done
    curl_imgreg --upload-file "{${upload_files#,}}" "$__upload/$VARIANT.tmp/"
    curl_imgreg -DELETE "$__upload/$VARIANT.old/" || info "404 => No previous %s.old/ to delete" "$VARIANT"
    curl_imgreg -XMOVE "$__upload/$VARIANT/" --header "Destination:$__upload/$VARIANT.old/" || info "404 => No previous %s/ to move to %s.old/" "$VARIANT" "$VARIANT"
    kill $lock_pid
    curl_imgreg -XMOVE "$__upload/$VARIANT.tmp/" --header "Destination:$__upload/$VARIANT/"
    curl_imgreg -DELETE "$__upload/$VARIANT/lock"
  fi
}

sha256() { sha256sum "$1" | cut -d ' ' -f1; }

wait_for_unlock() {
  local lock_dir=${1%'/'} locked_until locked_for
  while locked_until=$(curl_imgreg "$lock_dir/lock" 2>/dev/null); do
    locked_for=$(( locked_until - $(date +%s) ))
    [[ $locked_for -gt 0 ]] || break
    info "%s is locked for %d seconds, waiting for lock release" "$lock_dir" "$locked_for"
    sleep $locked_for
  done
}

keep_locked() {
  local lock_dir=${1%'/'}
  while true; do
    printf "%d" "$(( $(date +%s) + 60 ))" >/workspace/artifacts/lock
    curl_imgreg --upload-file /workspace/artifacts/lock "$lock_dir/"
    sleep 50
  done
}

curl_imgreg() {
  curl --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -fL --no-progress-meter --connect-timeout 5 \
    --retry 10 --retry-delay 60 \
    "$@"
}

main "$@"
