#!/bin/bash

# Prerequisite check(s) for module.
check() {
  require_kernel_modules squashfs loop || return 1
  return 0
}

# Module dependency requirements.
depends() {
  local modules=(systemd-journald overlay-root)
  ! $DEBUG || modules+=(bash)
  echo "${modules[*]}"
  return 0
}

# Install the required file(s) and directories for the module in the initramfs.
install() {
  inst_binary sha256sum
  ! $DEBUG || inst_binary cat nano less
  inst \
    /etc/systemd/system.conf.d/disk-uuids.conf \
    /etc/systemd/system.conf.d/variant.conf
  # shellcheck disable=SC2154
  inst "$moddir/system/restore-machine-id.service" "$systemdsystemconfdir/restore-machine-id.service"
  inst "$moddir/system/copy-rootimg.service" "$systemdsystemconfdir/copy-rootimg.service"
  inst "$moddir/system/sysroot.mount" "$systemdsystemconfdir/sysroot.mount"
  # shellcheck disable=SC2154
  $SYSTEMCTL -q --root "$initdir" enable \
    restore-machine-id.service \
    sysroot.mount
  # shellcheck disable=SC2154
  rm "${initdir}${systemdutildir}"/system-generators/systemd-gpt-auto-generator
  ln -sf ../run/machine-id "$initdir/etc/machine-id"

  # Skip root checking
  inst_hook cmdline 00 "$moddir/parse-squashfs-root.sh"
  return 0
}
