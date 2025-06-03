#!/usr/bin/env bash

build_bootimg() {
  info "Building RaspberryPI boot.img"

  local image_type
  for image_type in "${IMAGE_TYPES[@]}"; do
    mkdir -p "/workspace/rpi-bootimg-staging.$image_type/phxc"
    verbose "Staging RPi firmware & configuration files (%s)" "$image_type"
    case $VARIANT in
      rpi2|rpi3)
        cp /workspace/boot/vmlinuz "/workspace/rpi-bootimg-staging.$image_type/kernel7.img"
        cp /workspace/boot/initramfs.img "/workspace/rpi-bootimg-staging.$image_type/initramfs7"
        ;;
      rpi4)
        cp /workspace/boot/vmlinuz "/workspace/rpi-bootimg-staging.$image_type/kernel8.img"
        cp /workspace/boot/initramfs.img "/workspace/rpi-bootimg-staging.$image_type/initramfs8"
        ;;
      rpi5)
        cp /workspace/boot/vmlinuz "/workspace/rpi-bootimg-staging.$image_type/kernel_2712.img"
        cp /workspace/boot/initramfs.img "/workspace/rpi-bootimg-staging.$image_type/initramfs_2712"
        ;;
      *) printf "Unknown rpi* variant: %s\n" "$VARIANT" >&2; return 1 ;;
    esac
    cp -r /workspace/boot/firmware/* "/workspace/rpi-bootimg-staging.$image_type"
    printf "console=ttyS0,115200 console=tty0 %s cgroup_enable=memory" "${KERNEL_CMDLINE[*]}" \
      >"/workspace/rpi-bootimg-staging.$image_type/cmdline.txt"
    [[ $image_type != empty-pw ]] || printf " phxc.empty-pw" >>"/workspace/rpi-bootimg-staging.$image_type/cmdline.txt"
    cp "/workspace/boot/config-${VARIANT}-bootimg.txt" "/workspace/rpi-bootimg-staging.$image_type/config.txt"
    cp "/workspace/boot/config-${VARIANT}-bootimg.txt" "/workspace/rpi-bootimg-staging.$image_type/tryboot.txt"
    cp "/workspace/boot/config-${VARIANT}-boot.txt" "/workspace/boot-staging.$image_type/config.txt"
    cp "/workspace/boot/config-${VARIANT}-boot.txt" "/workspace/boot-staging.$image_type/tryboot.txt"
  done

  verbose "Calculating the required boot.img size"
  local block_size_b=512
  local bootimg_fat16_table_size_b=$(( 512 * 1024 )) bootimg_files_size_b
  bootimg_files_size_b=$(($(du -sB$block_size_b /workspace/rpi-bootimg-staging.empty-pw | cut -d$'\t' -f1) * block_size_b))
  # The extra 256 * block_size_b is wiggleroom for directories, signatures, and configs
  local disk_size_b=$((
    (
      bootimg_fat16_table_size_b +
      bootimg_files_size_b +
      256 * block_size_b +
      block_size_b - 1
    ) / block_size_b * block_size_b
  ))

  verbose "Creating boot.rpi-otp.img for disk encryption with RPi OTP"
  truncate -s"$disk_size_b" /artifacts/boot.rpi-otp.img
  mkfs.vfat -n "RPI-RAMDISK" /artifacts/boot.rpi-otp.img
  mcopy -sbQmi /artifacts/boot.rpi-otp.img /workspace/rpi-bootimg-staging.rpi-otp/* ::/

  verbose "Creating boot.img signature file"
  printf "%s\nts: %d\n" "$(sha256 /artifacts/boot.rpi-otp.img)" "$(date -u +%s)" \
    >/artifacts/boot.rpi-otp.sig
  if [[ -e $SB_KEY ]]; then
    verbose "Adding boot.img signature to signature file"
    local bootimg_sig
    bootimg_sig=$(openssl dgst -sign "$SB_KEY" -sha256 /artifacts/boot.rpi-otp.img | xxd -p -c0)
    printf "rsa2048: %s\n" "$bootimg_sig" >>/artifacts/boot.rpi-otp.sig
  fi

  verbose "Creating boot.img for disk encryption with an empty password"
  printf " phxc.empty-pw" >>/workspace/rpi-bootimg-staging.empty-pw/cmdline.txt
  truncate -s"$disk_size_b" /artifacts/boot.empty-pw.img
  mkfs.vfat -n "RPI-RAMDISK" /artifacts/boot.empty-pw.img
  mcopy -sbQmi /artifacts/boot.empty-pw.img /workspace/rpi-bootimg-staging.empty-pw/* ::/

  verbose "Creating boot.empty-pw.img signature file"
  printf "%s\nts: %d\n" "$(sha256 /artifacts/boot.empty-pw.img)" "$(date -u +%s)" \
    >/artifacts/boot.empty-pw.sig

  ln -s /artifacts/boot.rpi-otp.img /workspace/boot-staging.rpi-otp/boot.img
  ln -s /artifacts/boot.rpi-otp.sig /workspace/boot-staging.rpi-otp/boot.sig
  ln -s /artifacts/boot.empty-pw.img /workspace/boot-staging.empty-pw/boot.img
  ln -s /artifacts/boot.empty-pw.sig /workspace/boot-staging.empty-pw/boot.sig
}
