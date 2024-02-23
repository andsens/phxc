#!/bin/sh
# Source: https://github.com/andsens/bootstrap-vz/blob/fcdc6993f59e521567fb101302b02312e741b88c/bootstrapvz/plugins/minimize_size/assets/bootstrap-script.sh

extract_dpkg_deb_data () {
  pkg="$1"
  exclude_files=$(mktemp)
  dpkg-deb --fsys-tarfile "$pkg" | tar -t | \
      grep '\./usr/share/locale/.\+\|\./usr/share/man/.\+\|\./usr/share/doc/.\+' | \
      grep --invert-match --fixed-strings '/usr/share/locale/locale.alias
/usr/share/man/man1
/usr/share/man/man2
/usr/share/man/man3
/usr/share/man/man4
/usr/share/man/man5
/usr/share/man/man6
/usr/share/man/man7
/usr/share/man/man8
/usr/share/man/man9' >"$exclude_files" || true
  # List all files in $pkg and run them through the filter
  dpkg-deb --fsys-tarfile "$pkg" | tar --exclude-from "$exclude_files" -xf -
  rm "$exclude_files"
}

# Direct copypasta from the debootstrap script where it determines
# which script to run. We do exactly the same but leave out the
# if [ "$4" != "" ] part so that we can source the script that
# should've been sourced in this scripts place.

SCRIPT="$DEBOOTSTRAP_DIR/scripts/$SUITE"
if [ -n "$VARIANT" ] && [ -e "${SCRIPT}.${VARIANT}" ]; then
  SCRIPT="${SCRIPT}.${VARIANT}"
fi

# shellcheck disable=SC1090
. "$SCRIPT"
