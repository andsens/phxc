#!/bin/bash

# Prerequisite check(s) for module.
check() {
  require_kernel_modules squashfs loop || return 1
  # shellcheck disable=SC2154
  [[ -d /lib/modules/$kernel/kernel/fs/overlayfs ]] || return 1
  return 0
}

# Module dependency requirements.
depends() {
  local modules=(systemd-journald)
  [[ $VARIANT = rpi* ]] || modules+=(tpm2-tss)
  ! $DEBUG || modules+=(bash debug)
  echo "${modules[*]}"
  return 0
}

installkernel() {
  instmods overlay
}

# Install the required file(s) and directories for the module in the initramfs.
# shellcheck disable=SC2154
install() {
  local pkgroot=/usr/local/lib/upkg/.upkg/phxc
  inst_multiple sha256sum jq
  if $DEBUG; then
    inst_multiple cat nano less lsblk
  fi
  inst /etc/systemd/system.conf.d/disk-uuids.conf
  inst /etc/systemd/system.conf.d/variant.conf

  local src unit enable_units
  for src in "$pkgroot/bootstrap/systemd-units/initramfs"/*; do
    unit=$(basename "$src")
    if [[ ! $DEBUG && $unit == sysroot-mnt-overlay\\x2dupper.mount ]]; then
      continue
    fi
    if [[ $VARIANT = rpi* ]]; then
      [[ $unit != crypttab-tpm2.service ]] || continue
    else
      [[ $unit != crypttab-rpi-otp.service ]] || continue
    fi
    inst "$src" "$systemdsystemconfdir/$unit"
    ! grep -q '^\[Install\]$' "$src" || enable_units+=("$unit")
  done

  $SYSTEMCTL -q --root "$initdir" enable "${enable_units[@]}"

  ! $DEBUG || mkdir -p /mnt/overlay-upper

  rm "${initdir}${systemdutildir}"/system-generators/systemd-gpt-auto-generator
  ln -sf ../run/machine-id "$initdir/etc/machine-id"

  # Skip root checking
  inst_hook cmdline 00 "$moddir/parse-squashfs-root.sh"
  mkdir "$initdir/boot"
  mkdir -p "$initdir/overlay/image" "$initdir/overlay/rw"
  return 0
}
