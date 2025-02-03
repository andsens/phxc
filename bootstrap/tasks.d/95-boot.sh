#!/usr/bin/env bash

PACKAGES+=(
  systemd systemd-sysv # systemd bootup
  dosfstools # Used for mounting ESP
  dracut # initramfs, replaced with tiny-initramfs when done
)
PACKAGES_TMP+=(
  dracut-network dropbear # for entering the recovery key (+ connection info message)
  fatresize # boot partition expansion
  systemd-boot-efi # EFI stub for UKI
)

case $VARIANT in
  amd64|arm64) PACKAGES+=(
    "linux-image-$VARIANT" # kernel
    efibootmgr # UEFI boot entries
    tpm2-tools # pulls in TPM2 library deps for systemd-pcrextend
    binutils # Need objcopy & objdump to generate PCR signatures in update-boot
  ) ;;
  rpi*)
  curl -Lso/etc/apt/trusted.gpg.d/raspberrypi.asc http://archive.raspberrypi.com/debian/raspberrypi.gpg.key
  cat <<EOF >/etc/apt/sources.list.d/raspberrypi.sources
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: bookworm
Components: main
EOF
  PACKAGES+=(
    linux-image-rpi-2712 # kernel optimized for rpi
    raspi-firmware # rpi firmware drivers
  )
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

  mkdir /efi

  if [[ $VARIANT = rpi5 ]]; then
    # Remove Raspberry Pi 4 boot code
    rm boot/firmware/bootcode.bin boot/firmware/fixup*.dat boot/firmware/start*.elf
  fi

  # Re-enable initramfs updates
  unset INITRD
  local kernver
  kernver=$(echo /lib/modules/*)
  kernver=${kernver#'/lib/modules/'}
  dracut --force --kver "$kernver"
  mv "/boot/initrd.img-$kernver" /boot/initramfs.img
  mv "$(realpath /vmlinuz)" /boot/vmlinuz
  rm /vmlinuz /vmlinuz.old

  apt-get install -qq tiny-initramfs
  rm -rf /etc/dracut.conf.d /usr/lib/dracut # Remove the leftovers we copied into the image

  # Copy efi stub to /boot so create-boot-image can use it for the UKI, but uninstall it from the image
  cp -r /usr/lib/systemd/boot/efi /boot/systemd-boot-efi
}
