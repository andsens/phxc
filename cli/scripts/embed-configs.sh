#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
source "$PKGROOT/.upkg/records.sh/records.sh"

main() {
  local disk_info block_size_b sector_start sector_count
  disk_info=$(fdisk -lo Start,Sectors /workspace/disk.img)
  [[ $disk_info =~ Sector\ size.*:\ ([0-9]+)\  ]] || fatal 'Unable to parse block size from fdisk output:\n%s' "$disk_info"
  block_size_b=${BASH_REMATCH[1]}
  [[ $disk_info =~ ([0-9]+)\ +([0-9]+)$  ]] || fatal 'Unable to parse ESP sector start/count from fdisk output:\n%s' "$disk_info"
  sector_start=${BASH_REMATCH[1]}
  sector_count=${BASH_REMATCH[2]}
  dd if=/workspace/disk.img of=/workspace/esp.img bs="$block_size_b" skip="$sector_start" count="$sector_count"
  mcopy -sbQmi /workspace/esp.img /workspace/embed-configs/* ::/phxc/
  dd if=/workspace/esp.img of=/workspace/disk.img bs="$block_size_b" seek="$sector_start" conv=notrunc
}

main "$@"
