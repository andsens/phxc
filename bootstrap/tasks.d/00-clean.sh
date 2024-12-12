#!/usr/bin/env bash

clean() {
  rm /etc/fstab
  # initramfs-tools get installed for some reason
  # even though we select dracut in the same install as we select the kernel image
  apt-get purge initramfs-tools
  if ! $DEBUG; then
    PACKAGES_PURGE+=(
      libc-l10n
    )
    find \
      /usr/share/doc /usr/share/man /usr/share/locale \
      -mindepth 1 -maxdepth 1 \
      \( -not -path '/usr/share/man/man[0-9]' \) -a \
      \( -not -path /usr/share/locale/locale.alias \) \
      -print0 | xargs -0 rm -rf
  fi
}
