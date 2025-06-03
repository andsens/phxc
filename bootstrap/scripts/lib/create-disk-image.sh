#!/usr/bin/env bash

create_disk_image() {

  local image_type
  for image_type in "${IMAGE_TYPES[@]}"; do
    info "Building disk image from artifacts (%s)" "$image_type"

    verbose "Calculating size of boot partition (%s)" "$image_type"
    local block_size_b=512
    local boot_files_size_b boot_reserved_b=$((1024 * 1024 * 4))
    boot_files_size_b=$((
        $(du -sLB$block_size_b "/workspace/boot-staging.$image_type" | cut -d$'\t' -f1) * block_size_b
    ))
    local boot_fat32_table_size_b=$(( (2 * ((boot_files_size_b + boot_reserved_b) / 1024 / 1024) + 20) * 1024 ))
    local boot_size_b=$((
      (
        boot_fat32_table_size_b +
        boot_files_size_b +
        boot_reserved_b +
        block_size_b - 1
      ) / block_size_b * block_size_b
    ))

    local boot_partition_name=EFI-SYSTEM
    [[ $VARIANT != rpi* ]] || boot_partition_name=RPI-BOOT

    verbose "Building boot partition (%s)" "$image_type"
    truncate -s"$boot_size_b" "/artifacts/boot.$image_type.img"
    mkfs.vfat -n $boot_partition_name -F 32 "/artifacts/boot.$image_type.img"
    mcopy -sbQmi "/artifacts/boot.$image_type.img" "/workspace/boot-staging.$image_type"/* ::/

    verbose "Calculating size of disk image (%s)" "$image_type"
    local gpt_size_b=$((33 * 512)) partition_offset_b=$((1024 * 1024))
    local disk_size_b=$((
      (
        partition_offset_b +
        boot_size_b +
        gpt_size_b +
        block_size_b - 1
      ) / block_size_b * block_size_b
    ))

    verbose "Building disk image (%s)" "$image_type"
    local partition_type=$ESP_PART_TYPE_UUID
    # Let boot partition on rpi be a normal partition for easier mounting on windows
    [[ $VARIANT != rpi* ]] || partition_type=$MSBDP_PART_TYPE_UUID
    truncate -s"$disk_size_b" "/artifacts/disk.$image_type.img"
    sfdisk -q "/artifacts/disk.$image_type.img" <<EOF
label: gpt
start=$(( partition_offset_b / block_size_b )) size=$(( boot_size_b / block_size_b )), type=$partition_type, bootable, uuid=$BOOT_UUID
EOF
    dd if="/artifacts/boot.$image_type.img" of="/artifacts/disk.$image_type.img" \
      bs=$block_size_b seek=$((partition_offset_b / block_size_b)) count=$((boot_size_b / block_size_b)) conv=notrunc \
      status=none
  done
}

create_disk_image "$@"
