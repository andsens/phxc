#!/bin/bash

# Prerequisite check(s) for module.
check() {
  require_kernel_modules squashfs loop || return 1
  return 0
}

# Module dependency requirements.
depends() {
  echo "bash systemd-resolved systemd-networkd overlay-root"
  return 0
}

# Install the required file(s) and directories for the module in the initramfs.
install() {
  inst_binary \
    grep cut xxd dd sha256sum \
    lsblk \
    ip socat wget \
    jq flock \
    basename dirname realpath
  inst /usr/local/share/ca-certificates/phoenix-cluster-root.crt
  inst \
    /usr/local/lib/phoenix-cluster/node.sh \
    /etc/systemd/system.conf.d/disk-uuids.conf \
    /etc/systemd/system.conf.d/variant.conf \
    /etc/systemd/system/mount-boot.service

  # shellcheck disable=SC2154
  inst "$moddir/system/restore-machine-id.service" "$systemdsystemconfdir/restore-machine-id.service"
  inst "$moddir/system/copy-rootimg.service" "$systemdsystemconfdir/copy-rootimg.service"
  inst "$moddir/system/create-node-state.service" "$systemdsystemconfdir/create-node-state.service"
  inst "$moddir/system/rootimg.target" "$systemdsystemconfdir/rootimg.target"
  inst "$moddir/system/sysroot.mount" "$systemdsystemconfdir/sysroot.mount"
  inst "$moddir/system/verify-rootimg.service" "$systemdsystemconfdir/verify-rootimg.service"
  # shellcheck disable=SC2154
  mkdir "$initdir/boot"

  $SYSTEMCTL -q --root "$initdir" enable \
    restore-machine-id.service \
    move-rootimg.service \
    sysroot.mount
  # shellcheck disable=SC2154
  rm "${initdir}${systemdutildir}"/system-generators/systemd-gpt-auto-generator
  ln -sf ../run/machine-id "$initdir/etc/machine-id"

  # Skip root checking
  inst_hook cmdline 00 "$moddir/parse-squashfs-root.sh"
  return 0
}
