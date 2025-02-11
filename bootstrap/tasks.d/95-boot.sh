#!/usr/bin/env bash

PACKAGES+=(
  systemd systemd-sysv # systemd bootup
  dosfstools # Used for mounting ESP
  dracut # initramfs
)
PACKAGES_TMP+=(
  dracut-network dropbear # for entering the recovery key (+ connection info message)
  mtools util-linux # wipefs, minfo, mcopy needed for ESP rebuild
)

case $VARIANT in
  amd64|arm64) PACKAGES+=(
    "linux-image-$VARIANT" # kernel
    efibootmgr # UEFI boot entries
    tpm2-tools # pulls in TPM2 library deps for systemd-pcrextend
    binutils # Need objcopy & objdump to generate PCR signatures in update-boot
  )
  PACKAGES_TMP+=(
    systemd-boot-efi # EFI stub for UKI
  )
  ;;
  rpi*)
  # See 30-rpi.sh
  ;;
  *) printf "Unknown variant: %s\n" "$VARIANT" >&2; return 1 ;;
esac

FILES_ENVSUBST+=(
  /usr/lib/dracut/modules.d/99phxc/fstab # Contains $ROOT_SHA256, will be handled by create-boot-image
  /etc/fstab.tmp
)

# Disable initramfs updates until we are ready
export INITRD=No

boot() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system.conf.d/efi-arch.conf \
       /etc/systemd/system/init-efi-bootmenu.service
  fi
  # Enable serial console
  systemctl enable serial-getty@ttyS0

  if [[ $VARIANT = rpi5 ]]; then
    cp "$PKGROOT/bootstrap/assets/config-rpi5-bootimg.txt" /boot
    cp "$PKGROOT/bootstrap/assets/config-rpi5-esp.txt" /boot
  else
    # Copy efi stub to /boot so create-boot-image can use it for the UKI, but uninstall it from the image
    cp -r /usr/lib/systemd/boot/efi /boot/systemd-boot-efi
  fi

  # Re-enable initramfs updates
  unset INITRD
  local kernver
  kernver=$(readlink /vmlinuz)
  kernver=${kernver#'boot/vmlinuz-'}
  dracut --force --kver "$kernver"
}

boot_cleanup() {
  rm -rf /usr/lib/dracut # Remove the leftovers we copied into the image
}
