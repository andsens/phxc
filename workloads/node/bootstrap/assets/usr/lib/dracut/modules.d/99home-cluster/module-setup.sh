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
# copy_exec /usr/bin/mountpoint /bin

  inst_binary jq flock socat curl basename ip grep cut lsblk xxd dd sha256sum
  inst /usr/local/share/ca-certificates/home-cluster-root.crt /usr/local/share/ca-certificates/home-cluster-root.crt
  inst /usr/local/lib/upkg/.upkg/home-cluster/.upkg/records.sh/records.sh /usr/lib/home-cluster/records.sh
  inst /usr/local/lib/upkg/.upkg/home-cluster/.upkg/trap.sh/trap.sh /usr/lib/home-cluster/trap.sh
  inst "$moddir/lib/common.sh" /usr/lib/home-cluster/common.sh
  inst "$moddir/lib/curl-boot-server.sh" /usr/lib/home-cluster/curl-boot-server.sh
  inst "$moddir/lib/disk-uuids.sh" /usr/lib/home-cluster/disk-uuids.sh
  inst "$moddir/lib/node.sh" /usr/lib/home-cluster/node.sh

  inst "$moddir/bin/create-node-state" /usr/bin/create-node-state
  inst "$moddir/bin/find-boot-server" /usr/bin/find-boot-server
  inst "$moddir/bin/get-rootimg" /usr/bin/get-rootimg

  inst "$moddir/units/find-boot-server.service" "$systemdsystemconfdir/find-boot-server.service"
  inst "$moddir/units/create-node-state@.service" "$systemdsystemconfdir/create-node-state@.service"
  # inst "$moddir/units/boot.mount" "$systemdsystemconfdir/boot.mount"
  inst "$moddir/units/get-rootimg.service" "$systemdsystemconfdir/get-rootimg.service"
  inst "$moddir/units/sysroot.mount" "$systemdsystemconfdir/sysroot.mount"

  # Enable systemd type unit(s)
  $SYSTEMCTL -q --root "$initdir" add-wants sysinit.target "create-node-state@${VARIANT:?}.service"
  $SYSTEMCTL -q --root "$initdir" enable find-boot-server.service
  $SYSTEMCTL -q --root "$initdir" enable "create-node-state@${VARIANT:?}.service"
  $SYSTEMCTL -q --root "$initdir" enable get-rootimg.service
  $SYSTEMCTL -q --root "$initdir" enable sysroot.mount
  # $SYSTEMCTL -q --root "$initdir" enable "boot.mount"

  inst_hook cmdline 00 "$moddir/parse-squashfs-root.sh"
  return 0
}
