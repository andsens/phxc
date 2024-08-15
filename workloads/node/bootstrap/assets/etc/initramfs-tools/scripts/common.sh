#!/usr/bin/env bash

# shellcheck source=../../../../../../../.upkg/records.sh/records.sh
source "$PKGROOT/records.sh"
[[ ${debug:-n} != y ]] || LOGLEVEL=debug
# shellcheck source=./node-state.sh
source "$PKGROOT/node-state.sh"
# shellcheck source=./node-config.sh
source "$PKGROOT/node-config.sh"
# shellcheck source=./curl-boot-server.sh
source "$PKGROOT/curl-boot-server.sh"
