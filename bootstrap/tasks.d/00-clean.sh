#!/usr/bin/env bash

# bash parsing workaround: extglob must be enabled when the function is parsed
shopt -s extglob
clean() {
  rm /etc/fstab
  if $DEBUG; then
    # Don't filter out locales and manpages when installing packages
    rm /etc/dpkg/dpkg.cfg.d/excludes
  else
    PACKAGES_PURGE+=(
      libc-l10n
      libicu72
    )
    # Remove existing docs, manpages, locales that came as part of the container
    shopt -s extglob
    rm -rf /usr/share/doc/*/!(copyright)
    rm -rf /usr/share/man/!(man[1-9])
    rm -rf /usr/share/locale/!(locale.alias)
    shopt -u extglob
    for dir in /usr/share/doc/*; do
      [[ -e $dir/copyright ]] || rm -rf "$dir"
    done
    unset dir
  fi
}
shopt -u extglob
