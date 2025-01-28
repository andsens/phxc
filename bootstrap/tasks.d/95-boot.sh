#!/usr/bin/env bash

PACKAGES+=(
  systemd systemd-sysv # systemd bootup
  dosfstools # Used for mounting ESP
  systemd-resolved # DNS resolution setup
  zstd # initramfs compression
)
PACKAGES_TMP+=(dracut)

case $VARIANT in
  amd64) PACKAGES+=(
    linux-image-amd64 # kernel
    efibootmgr # UEFI boot entries
    tpm2-tools # pulls in TPM2 library deps for systemd-pcrextend
    binutils # Need objcopy & objdump to generate PCR signatures in update-boot
  ) ;;
  arm64) PACKAGES+=(
    linux-image-arm64 # kernel
    efibootmgr # UEFI boot entries
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

# Installing the kernel & dracut at the same time somehow also installs initramfs-tools
# Install a dummy package prior to that to prevent it
mkdir /workspace/initramfs-tools
(cd /workspace/initramfs-tools && equivs-build /usr/local/lib/upkg/.upkg/phxc/bootstrap/assets/initramfs-tools)
dpkg -i /workspace/initramfs-tools/initramfs-tools_0.145_all.deb

# Disable initramfs updates until we are ready
export INITRD=No

boot() {
  if [[ $VARIANT = rpi* ]]; then
    rm /etc/systemd/system.conf.d/efi-arch.conf \
       /etc/systemd/system/init-efi-bootmenu.service \
       /usr/local/bin/get-efi-bootnum
  else
    chmod +x /usr/local/bin/get-efi-bootnum
  fi
  chmod +x /usr/local/bin/cordoned-reboot \
           /usr/local/bin/update-boot \
  # Enable serial console
  systemctl enable serial-getty@ttyS0

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
}
