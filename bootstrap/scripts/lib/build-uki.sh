#!/usr/bin/env bash

build_uki() {
  info "Creating unified kernel image"

  local kernver
  kernver=$(compgen -G '/workspace/root/usr/lib/modules/*')
  kernver=${kernver##*/}

  local efi_arch
  case "$VARIANT" in
    amd64) efi_arch=X64 ;;
    arm64) efi_arch=AA64 ;;
    *) fatal "Unknown variant: %s" "$VARIANT" ;;
  esac

  # Instead of installing systemd-boot-efi in the rather static create-boot-image image
  # Use the efi stub from the regularly updated actual image we are creating
  mkdir -p /usr/lib/systemd/boot
  ln -s /workspace/root/boot/systemd-boot-efi /usr/lib/systemd/boot/efi

  verbose "Creating uki.empty-pw.efi for disk encryption with an empty password"
  mkdir -p /workspace/boot-staging.empty-pw/EFI/BOOT
  /lib/systemd/ukify build \
    --uname="$kernver" \
    --linux=/workspace/root/boot/vmlinuz \
    --initrd=/artifacts/initramfs.img \
    --cmdline="$(printf "%s phxc.empty-pw" "${KERNEL_CMDLINE[*]}")" \
    --output=/artifacts/uki.empty-pw.efi

  verbose "Creating uki.efi for disk encryption with TPM2"
  mkdir -p /workspace/boot-staging.tpm2/EFI/BOOT
  local uki_secure_opts=()
  # Sign UKI if secureboot key & cert are present
  if [[ -e $SB_KEY && -e $SB_CRT ]]; then
    verbose "Adding secureboot signing parameters for uki.efi creation"
    uki_secure_opts+=("--secureboot-private-key=$SB_KEY" "--secureboot-certificate=$SB_CRT")
    openssl x509 -in "$SB_CRT" -outform der -out /workspace/boot-staging.tpm2/phxc/secureboot.der
  fi
  /lib/systemd/ukify build "${uki_secure_opts[@]}" \
    --uname="$kernver" \
    --linux=/workspace/root/boot/vmlinuz \
    --initrd=/artifacts/initramfs.img \
    --cmdline="$(printf "%s" "${KERNEL_CMDLINE[*]}")" \
    --output=/artifacts/uki.tpm2.efi

  ln -s /artifacts/uki.empty-pw.efi /workspace/boot-staging.empty-pw/EFI/BOOT/BOOT${efi_arch}.EFI
  ln -s /artifacts/uki.tpm2.efi /workspace/boot-staging.tpm2/EFI/BOOT/BOOT${efi_arch}.EFI
}
