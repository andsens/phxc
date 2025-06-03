#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/.upkg/records.sh/records.sh"
source "$PKGROOT/lib/common-context/uuids.sh"

main() {
  SB_KEY=/workspace/secureboot/tls.key
  # shellcheck disable=SC2034
  SB_CRT=/workspace/secureboot/tls.crt
  if [[ -e $SB_KEY ]]; then
    info "Checking secureboot key"
    openssl rsa -in $SB_KEY -noout -check || fatal "Secureboot key must be a 2048 bit RSA key"
    [[ $(openssl rsa -in $SB_KEY -noout -text) =~ Private-Key:\ \(([0-9]+)\ bit, ]] || fatal "Unable to determine secureboot keysize"
    [[ ${BASH_REMATCH[1]} = 2048 ]] || fatal "Secureboot key must be a 2048 bit RSA key (got %d bit)" "${BASH_REMATCH[1]}"
  fi

  IMAGE_TYPES=(empty-pw)
  if [[ $VARIANT = rpi* ]]; then
    IMAGE_TYPES+=(rpi-otp)
  else
    IMAGE_TYPES+=(tpm2)
  fi

  KERNEL_CMDLINE=()
  if $DEBUG; then
    KERNEL_CMDLINE+=("rd.shell")
    # KERNEL_CMDLINE+=("rd.break")
  fi

  mkdir /artifacts

  create_root_img
  inject_rootimg_sha256

  if [[ $VARIANT = rpi* ]]; then
    source "$PKGROOT/bootstrap/scripts/lib/build-bootimg.sh"
    build_bootimg
  else
    source "$PKGROOT/bootstrap/scripts/lib/build-uki.sh"
    build_uki
  fi
  source "$PKGROOT/bootstrap/scripts/lib/create-disk-image.sh"
  create_disk_image

  if ! $DEBUG; then
    rm /artifacts/initramfs.img
    local image_type
    for image_type in "${IMAGE_TYPES[@]}"; do
      rm "boot.$image_type.img"
    done
  fi

  if [[ -n $CHOWN ]]; then
    local artifact
    for artifact in /artifacts/*; do
      chown "$CHOWN:$CHOWN" "$artifact"
    done
  fi
}

create_root_img() {
  info "Creating squashfs image"

  local noprogress=
  [[ -t 1 ]] || noprogress=-no-progress
  mksquashfs /workspace/root /artifacts/root.img -noappend -quiet  -comp zstd $noprogress -wildcards -e 'boot/*'

  # Hash the root image so we can verify it during boot
  local rootimg_sha256 image_type
  rootimg_sha256=$(sha256 /artifacts/root.img)
  for image_type in "${IMAGE_TYPES[@]}"; do
    mkdir -p "/workspace/boot-staging.$image_type/phxc"
    ln -s /artifacts/root.img "/workspace/boot-staging.$image_type/phxc/root.$rootimg_sha256.img"
  done
  printf "%s\n" "$rootimg_sha256" >/artifacts/root.img.sha256
}

inject_rootimg_sha256() {
  info "Injecting image checksum into initramfs"

  local rootimg_sha256
  rootimg_sha256=$(cat /artifacts/root.img.sha256)

  mkdir /workspace/initramfs
  verbose "Decompressing initramfs"
  (
    cd /workspace/initramfs
    cpio -id </workspace/root/boot/initramfs.img
  )
  cp /workspace/initramfs/etc/fstab /workspace/envsubst.tmp
  # shellcheck disable=SC2016
  ROOTIMG_SHA256=$rootimg_sha256 envsubst '${ROOTIMG_SHA256}' </workspace/envsubst.tmp >/workspace/initramfs/etc/fstab

  local share_phxc=/workspace/initramfs/usr/share/phxc
  mkdir "$share_phxc"
  printf '%s  /boot/phxc/root.%s.img\n' "$rootimg_sha256" "$rootimg_sha256" >"$share_phxc/root.img.sha256sum"
  printf '%s\n' "$rootimg_sha256" >"$share_phxc/root.img.sha256"

  verbose "Compressing initramfs"
  (
    cd /workspace/initramfs
    find . -print0 | cpio -o --null --format=newc 2>/dev/null | zstd -15 >/artifacts/initramfs.img
  )
}

sha256() { sha256sum "$1" | cut -d ' ' -f1; }

main "$@"
