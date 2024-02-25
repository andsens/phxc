#!/usr/bin/env bash
# shellcheck disable=SC2034
# Not actually included, this is only intended for shellcheck to reference as a source file
BOOT_PARTITION=${BOOT_PARTITION:-/dev/loop0p2}
ESP_DEVICE=${ESP_DEVICE:-/dev/loop0p1}
BOOT_DEVICE=${BOOT_DEVICE:-"/dev/loop0"}
ROOT_PARTITION=${ROOT_PARTITION:-UUID=2497dc7b-3138-430c-8282-cc98e2b13718}
SWAPLIST=${SWAPLIST:-""}
PHYSICAL_BOOT_DEVICES="/dev/loop0"
