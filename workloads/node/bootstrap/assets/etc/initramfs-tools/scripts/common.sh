#!/usr/bin/env bash

# shellcheck source=../../../../../../../.upkg/records.sh/records.sh
source "$PKGROOT/records.sh"
[[ ${debug:-n} != y ]] || LOGLEVEL=debug
# shellcheck source=boot-state.sh
source "$PKGROOT/boot-state.sh"
