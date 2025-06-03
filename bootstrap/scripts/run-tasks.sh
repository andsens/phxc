#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/.upkg/records.sh/records.sh"
source "$PKGROOT/.upkg/collections.sh/collections.sh"
source "$PKGROOT/lib/common-context/uuids.sh"

export BOOT_TYPE_UUID=$ESP_PART_TYPE_UUID

case "$VARIANT" in
  amd64) export EFI_ARCH="X64" ;;
  arm64) export EFI_ARCH="AA64" ;;
esac

main() {
  mkdir /workspace
  export DEBIAN_FRONTEND=noninteractive

  # Enable non-free components
  sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources

  DEBCONF_SELECTIONS=(
    "debconf debconf/frontend        select  Noninteractive"
    "debconf debconf/priority        select  critical"
  )
  PACKAGES=()
  PACKAGES_TMP=(gettext)
  FILES_EXCLUDE=()
  FILES_ENVSUBST=()

  info "Including task files"
  local taskfile
  for taskfile in "$PKGROOT/bootstrap/tasks.d/"??-*.sh; do
    verbose "incl %s" "$(basename "$taskfile" .sh)"
    # shellcheck disable=SC1090
    source "$taskfile"
  done

  function run_tasks() {
    local suffix=$1 taskfile task
    for taskfile in "$PKGROOT/bootstrap/tasks.d/"??-*.sh; do
      task=$(basename "$taskfile" .sh)
      task=${task#[0-9][0-9]-}
      task=${task//[^a-z0-9_]/_}$suffix
      if [[ $(type "$task" 2>/dev/null) = "$task is a function"* ]]; then
        info "run %s" "$task"
        "$task"
      fi
    done
  }

  run_tasks "_pre_copy"

  info "Copying files"
  local src dest
  while IFS= read -r -d $'\0' src; do
    dest=${src#"$PKGROOT/bootstrap/root"}
    mkdir -p "$(dirname "$dest")"
    if contains_element "$dest" "${FILES_EXCLUDE[@]}"; then
      verbose "skip %s" "$dest"
    elif [[ $(basename "$src") = .gitkeep ]]; then
      verbose "skip %s" "$dest"
    else
      verbose "copy %s" "$dest"
      cp -PT --preserve=all "$src" "$dest"
    fi
  done < <(find "$PKGROOT/bootstrap/root" \( -type f -o -type l \) -print0)

  info "Copying systemd units"
  local unit enable_units unit_files=$PKGROOT/bootstrap/systemd-units
  while IFS= read -r -d $'\0' src; do
    unit=$(basename "$src")
    dest=/etc/systemd/system/$unit
    if contains_element "$dest" "${FILES_EXCLUDE[@]}"; then
      verbose "skip %s" "$dest"
    elif [[ $src = $unit_files/initramfs/* ]]; then
      verbose "skip %s" "$dest"
    else
      if grep -q '^\[Install\]$' "$src" && [[ $unit != *@* ]]; then
        enable_units+=("$unit")
      fi
      verbose "copy %s" "$unit"
      cp -PT --preserve=all "$src" "$dest"
    fi
  done < <(find "$unit_files" -type f -print0)

  info "Replacing variables in files"
  # shellcheck disable=SC2016
  local file replacements=('${BOOT_TYPE_UUID}' '${BOOT_UUID}' '${DATA_UUID}' '${DEBUG}' '${VARIANT}' '${EFI_ARCH}')
  for file in "${FILES_ENVSUBST[@]}"; do
    cp "$file" /workspace/envsubst.tmp
    verbose "vars %s" "$file"
    envsubst "${replacements[*]}" </workspace/envsubst.tmp >"$file"
  done
  rm -f /workspace/envsubst.tmp

  run_tasks "_pre_install"

  printf "%s\n" "${DEBCONF_SELECTIONS[@]}" | debconf-set-selections

  # Update packages a second time in case any sources were added
  apt-get -qy update
  info "Upgrading all packages"
  apt-get upgrade -qy
  info "Installing packages: %s" "${PACKAGES[*]} ${PACKAGES_TMP[*]}"
  apt-get install -qy --no-install-recommends "${PACKAGES[@]}" "${PACKAGES_TMP[@]}"
  apt-mark auto "${PACKAGES_TMP[@]}"

  run_tasks ""

  info "Enabling systemd units"
  for unit in "${enable_units[@]}"; do
    [[ ! -e /etc/systemd/system/$unit ]] || systemctl enable "$unit"
  done

  apt-get autoremove -qy
  # shellcheck disable=SC2046
  apt-get purge -qy $(dpkg -l | grep '^rc' | awk '{print $2}')
  apt-get autoclean -qy

  run_tasks "_cleanup"

  # Enable service restarts
  rm /usr/sbin/policy-rc.d
}

main "$@"
