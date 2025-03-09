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
    amd64-microcode intel-microcode # Microcode updates that will be embedded in the UKI
  )
  ;;
  rpi*)
  # See rpi_kernel further down
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
    rpi_kernel
  fi
  # Enable serial console
  systemctl enable serial-getty@ttyS0

  if [[ $VARIANT = rpi5 ]]; then
    cp "$PKGROOT/bootstrap/assets/config-rpi5-bootimg.txt" /boot
    cp "$PKGROOT/bootstrap/assets/config-rpi5-esp.txt" /boot
    cp "$PKGROOT/bootstrap/assets/boot.conf" /boot
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
  # Disable initramfs updates again, so they won't be triggered by uninstalls
  export INITRD=No
}

boot_cleanup() {
  rm -rf /usr/lib/dracut # Remove the leftovers we copied into the image
}

rpi_kernel() {
  local kver kerneltmp rpi_suffix
  kerneltmp=$(mktemp -d)
  wget -qO>(tar -xzC "$kerneltmp" --strip-components=1) \
    "https://github.com/raspberrypi/firmware/archive/5eaa42401e9625415934c97baae5a8d65933768c.tar.gz"
  case "$VARIANT" in
    rpi2|rpi3) rpi_suffix=7 ;;
    rpi4) rpi_suffix=8 ;;
    rpi5) rpi_suffix=_2712 ;;
  esac
  uname_path="$kerneltmp/extra/uname_string${rpi_suffix}"
  kver=$(grep -o '^Linux version [^ ]\+' "$uname_path" | cut -d' ' -f3)
  mkdir /usr/lib/modules
  cp -r "$kerneltmp/modules/$kver" "/usr/lib/modules/$kver"
  cp "$kerneltmp/boot/kernel${rpi_suffix}.img" "/boot/vmlinuz-$kver"
  ln -s "boot/vmlinuz-$kver" /vmlinuz
  ln -s "boot/vmlinuz-$kver" /vmlinuz.old

  mkdir /boot/firmware
  cp -r "$kerneltmp/boot/overlays" /boot/firmware/overlays
  case "$VARIANT" in
    rpi2)
      cp "$kerneltmp/boot/start_x.elf" \
          "$kerneltmp/boot"/bcm*-rpi-2* \
          /boot/firmware
      ;;
    rpi3)
      cp "$kerneltmp/boot/start_x.elf" \
          "$kerneltmp/boot"/bcm2710-rpi-3* \
          /boot/firmware
      ;;
    rpi4)
      cp "$kerneltmp/boot/start4x.elf" \
          "$kerneltmp/boot"/bcm2711* \
          /boot/firmware
      ;;
    rpi5)
      cp "$kerneltmp/boot"/bcm2712* /boot/firmware
      ;;
  esac
  rm -rf "$kerneltmp"
}
