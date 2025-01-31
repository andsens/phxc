#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/.upkg/records.sh/records.sh"

export DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
export BOOT_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8
export LUKS_UUID=2a785738-5af5-4c13-88ae-e5f2d20e7049
case "$VARIANT" in
  amd64) export EFI_ARCH="X64" ;;
  arm64) export EFI_ARCH="AA64" ;;
esac

main() {
  mkdir -p /workspace/artifacts
  export DEBIAN_FRONTEND=noninteractive

  # Enable non-free components
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources

  PACKAGES_PURGE=(gettext)
  FILES_ENVSUBST=()

  info "Copying files"
  local src dest
  while IFS= read -r -d $'\0' src; do
    dest=${src#"$PKGROOT/bootstrap/root"}
    mkdir -p "$(dirname "$dest")"
    [[ $(basename "$src") != .gitkeep ]] || continue
    cp -PT --preserve=all "$src" "$dest"
  done < <(find "$PKGROOT/bootstrap/root" \( -type f -o -type l \) -print0)

  info "Copying systemd units"
  local unit enable_units unit_files=$PKGROOT/bootstrap/systemd-units
  while IFS= read -r -d $'\0' src; do
    [[ $src != $unit_files/initramfs/* ]] || continue
    unit=$(basename "$src")
    if grep -q '^\[Install\]$' "$src" && [[ $unit != *@* ]]; then
      enable_units+=("$unit")
    fi
    cp -PT --preserve=all "$src" "/etc/systemd/system/$unit"
  done < <(find "$unit_files" -type f -print0)

  PACKAGES=(apt-utils jq)
  PACKAGES_TMP=()
  local taskfile
  for taskfile in "$PKGROOT/bootstrap/tasks.d/"??-*.sh; do
    # shellcheck disable=SC1090
    source "$taskfile"
  done

  info "Replacing variables in files"
  # shellcheck disable=SC2016
  local file replacements=('${DISK_UUID}' '${BOOT_UUID}' '${DATA_UUID}' '${LUKS_UUID}' '${VARIANT}' '${EFI_ARCH}')
  for file in "${FILES_ENVSUBST[@]}"; do
    cp "$file" /workspace/envsubst.tmp
    envsubst "${replacements[*]}" </workspace/envsubst.tmp >"$file"
  done

  local all_packages=()
  readarray -t -d $'\n' all_packages < <(printf "%s\n" "${PACKAGES[@]}" "${PACKAGES_TMP[@]}" | sort -u)
  info "Upgrading all packages"
  apt-get upgrade -qq
  info "Installing packages: %s" "${all_packages[*]}"
  apt-get install -y --no-install-recommends "${all_packages[@]}"

  local task
  for taskfile in "$PKGROOT/bootstrap/tasks.d/"??-*.sh; do
    task=$(basename "$taskfile" .sh)
    task=${task#[0-9][0-9]-}
    task=${task//[^a-z0-9_]/_}
    info "Running %s" "$(basename "$taskfile")"
    if [[ $(type "$task" 2>/dev/null) = "$task is a function"* ]]; then
      eval "$task"
    else
      warning "%s had no task named %s" "$(basename "$taskfile")" "$task"
    fi
  done

  info "Enabling systemd units"
  for unit in "${enable_units[@]}"; do
    [[ ! -e /etc/systemd/system/$unit ]] || systemctl enable "$unit"
  done

  # `comm -13`: Only remove temp packages that don't also appear in PACKAGES_TMP
  local packages_purge=()
  readarray -t -d $'\n' packages_purge < <(\
    [[ ${#PACKAGES_TMP[@]} -eq 0 ]] || comm -13 <(printf "%s\n" "${PACKAGES[@]}" | sort -u) <(printf "%s\n" "${PACKAGES_TMP[@]}" | sort -u)
    [[ ${#PACKAGES_PURGE[@]} -eq 0 ]] || printf "%s\n" "${PACKAGES_PURGE[@]}"
  )
  apt-get purge -y "${packages_purge[@]}"
  apt-get autoremove -y
  apt-get autoclean
}

main "$@"
