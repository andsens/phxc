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
  local modules=(systemd-journald systemd-repart systemd-networkd)
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
  inst_multiple sha256sum jq lsblk mkfs.ext4 touch fatresize
  if $DEBUG; then
    inst_multiple cat nano less
  fi
  inst /etc/systemd/system.conf.d/disk-uuids.conf
  inst /etc/systemd/system.conf.d/variant.conf

  ### EFI partition ###
  inst "$moddir/repart.d/10-esp.conf" /etc/repart.d/10-esp.conf
  mkdir "$initdir/efi"

  ### Data partition ###
  # Setup via repart
  inst "$moddir/repart.conf" /etc/systemd/system/systemd-repart.service.d/repart.conf
  inst "$moddir/repart.d/60-data.conf" /etc/repart.d/60-data.conf
  inst "$moddir/crypttab" /etc/crypttab
  rm "$initdir/lib/dracut/hooks/cmdline/30-parse-crypt.sh" # Only thing the hook does is put in timeout configs for units it malparsed
  inst rpi-otp-disk-encryption-key

  if [[ $VARIANT != rpi* ]]; then
    # tss user setup, the tpm2-tss module seems to miss this
    inst "$moddir/tpm2-sysuser.conf" /usr/lib/sysusers.d/tpm2.conf
    mkdir "$initdir/var/lib/tpm"
    chown 101:102 "$initdir/var/lib/tpm"
  fi

  if [[ -e /home/admin/.ssh/authorized_keys ]]; then
    # Recovery key input via SSH
    inst_multiple /etc/systemd/network/zzz-dhcp.network /usr/bin/ip /usr/bin/dropbearkey
    inst /usr/sbin/dropbear /usr/bin/dropbear
    inst /home/admin/.ssh/authorized_keys /root/.ssh/authorized_keys
    mkdir "$initdir/etc/dropbear"
    chmod go-rwx -R "$initdir/root/.ssh"
    chown root:root "$initdir/root/.ssh/authorized_keys"
    # Mask systemd-ask-password-console.path so that only users authenticated via SSH can enter a password
    $SYSTEMCTL -q --root "$initdir" mask systemd-ask-password-console.path
  fi

  ### Install systemd units ###
  local src unit enable_units
  for src in "$pkgroot/bootstrap/systemd-units/initramfs"/*; do
    unit=$(basename "$src")
    if [[ ! $DEBUG && $unit == sysroot-mnt-overlay\\x2dupper.mount ]]; then
      continue
    fi
    if [[ $VARIANT != rpi* ]]; then
      [[ $unit != cryptsetup-rpi-otp.service ]] || continue
    fi
    inst "$src" "/etc/systemd/system/$unit"
    ! grep -q '^\[Install\]$' "$src" || enable_units+=("$unit")
  done
  $SYSTEMCTL -q --root "$initdir" enable "${enable_units[@]}"

  ### Root setup ###
  mkdir -p /mnt/overlay-upper
  mkdir -p "$initdir/overlay/image" "$initdir/overlay/rw"

  # Skip root checking
  inst_hook cmdline 00 "$moddir/parse-squashfs-root.sh"

  # See https://github.com/dracut-ng/dracut-ng/pull/1063
  # shellcheck disable=SC2046
  $SYSTEMCTL -q --root "$initdir" mask $(systemd-escape dev/gpt-auto-root.device)

  ### Rest ###
  ln -sf ../run/machine-id "$initdir/etc/machine-id"

  return 0
}
