#!/usr/bin/env bash
# shellcheck source-path=..

PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"
source "$PKGROOT/lib/mount.sh"
source "$PKGROOT/lib/settings.sh"
source "$PKGROOT/lib/vm.sh"
