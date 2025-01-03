#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/.upkg/records.sh/records.sh"

export DISK_UUID=caf66bff-edab-4fb1-8ad9-e570be5415d7
export BOOT_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8

main() {
  mkdir -p /workspace/artifacts
  export DEBIAN_FRONTEND=noninteractive

  # Enable non-free components
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
  apt-get update -qq

  # Install base deps
  # gettext -> envsubst
  apt-get install -y --no-install-recommends gettext

  info "Copying files"
  # shellcheck disable=SC2016
  local replacements=('${DISK_UUID}' '${BOOT_UUID}' '${DATA_UUID}' '${VARIANT}')

  local src dest files=$PKGROOT/bootstrap/root
  while IFS= read -r -d $'\0' src; do
    dest=${src#"$files"}
    mkdir -p "$(dirname "$dest")"
    envsubst "${replacements[*]}" <"$src" >"$dest"
  done < <(find "$files" -type f -print0)

  local unit enable_units unit_files=$PKGROOT/bootstrap/systemd-units
  while IFS= read -r -d $'\0' src; do
    unit=$(basename "$src")
    if grep -q '^\[Install\]$' "$src" && [[ $unit != *@* ]]; then
      enable_units+=("$unit")
    fi
    envsubst "${replacements[*]}" <"$src" >"/etc/systemd/system/$unit"
  done < <(find "$unit_files" -type f -print0)

  PACKAGES=(apt-utils jq)
  PACKAGES_TMP=()
  PACKAGES_PURGE=()
  local taskfile
  for taskfile in "$PKGROOT/bootstrap/tasks.d/"??-*.sh; do
    # shellcheck disable=SC1090
    source "$taskfile"
  done

  local all_packages=()
  readarray -t -d $'\n' all_packages < <(printf "%s\n" "${PACKAGES[@]}" "${PACKAGES_TMP[@]}" | sort -u)
  info "Installing packages: %s" "${all_packages[*]}"
  apt-get upgrade -qq
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
    comm -13 <(printf "%s\n" "${PACKAGES[@]}" | sort -u) <(printf "%s\n" "${PACKAGES_TMP[@]}" | sort -u)
    printf "%s\n" "${PACKAGES_PURGE[@]}"
  )
  apt-get purge -y "${packages_purge[@]}"
  apt-get autoremove -y
  apt-get autoclean
  rm -rf /var/lib/apt/lists/*
  rm /etc/apt/apt.conf.d/20apt-cacher-ng.conf
}

main "$@"
