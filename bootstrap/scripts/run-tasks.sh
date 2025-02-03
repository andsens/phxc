#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/.upkg/records.sh/records.sh"

export EFI_UUID=c427f0ed-0366-4cb2-9ce2-3c8c51c3e89e
export DATA_UUID=6f07821d-bb94-4d0f-936e-4060cadf18d8
case "$VARIANT" in
  amd64) export EFI_ARCH="X64" ;;
  arm64) export EFI_ARCH="AA64" ;;
esac

main() {
  mkdir -p /workspace/artifacts
  export DEBIAN_FRONTEND=noninteractive

  # Enable non-free components
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources

  PACKAGES=()
  PACKAGES_TMP=(gettext)
  FILES_ENVSUBST=()

  info "Copying files"
  local src dest
  while IFS= read -r -d $'\0' src; do
    dest=${src#"$PKGROOT/bootstrap/root"}
    mkdir -p "$(dirname "$dest")"
    [[ $(basename "$src") != .gitkeep ]] || continue
    verbose "Copying %s" "$dest"
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
    verbose "Copying %s" "$unit"
    cp -PT --preserve=all "$src" "/etc/systemd/system/$unit"
  done < <(find "$unit_files" -type f -print0)

  local taskfile
  for taskfile in "$PKGROOT/bootstrap/tasks.d/"??-*.sh; do
    verbose "Including task %s" "$taskfile"
    # shellcheck disable=SC1090
    source "$taskfile"
  done

  info "Replacing variables in files"
  # shellcheck disable=SC2016
  local file replacements=('${EFI_UUID}' '${DATA_UUID}' '${VARIANT}' '${EFI_ARCH}')
  for file in "${FILES_ENVSUBST[@]}"; do
    cp "$file" /workspace/envsubst.tmp
    verbose "Replace vars in %s" "$file"
    envsubst "${replacements[*]}" </workspace/envsubst.tmp >"$file"
  done
  rm -f /workspace/envsubst.tmp

  # Update packages a second time in case any sources were added
  apt-get -qq update
  info "Upgrading all packages"
  apt-get upgrade -qq
  info "Installing packages: %s" "${PACKAGES[*]} ${PACKAGES_TMP[*]}"
  apt-get install -qq --no-install-recommends "${PACKAGES[@]}" "${PACKAGES_TMP[@]}"
  apt-mark auto "${PACKAGES_TMP[@]}"

  local task cleanup_tasks
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
    if [[ $(type "${task}_cleanup" 2>/dev/null) = "$task is a function"* ]]; then
      cleanup_tasks+=("${task}_cleanup")
    fi
  done

  info "Enabling systemd units"
  for unit in "${enable_units[@]}"; do
    [[ ! -e /etc/systemd/system/$unit ]] || systemctl enable "$unit"
  done

  apt-get autoremove -qq
  # shellcheck disable=SC2046
  apt-get purge -qq $(dpkg -l | grep '^rc' | awk '{print $2}')
  apt-get autoclean -qq

  for task in "${cleanup_tasks[@]}"; do
    eval "$task"
  done
}

main "$@"
