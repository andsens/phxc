#!/usr/bin/env bash

# shellcheck source=../../../../../../../.upkg/records.sh/records.sh
source "$PKGROOT/records.sh"
[[ ${debug:-n} != y ]] || LOGLEVEL=debug
# shellcheck source=node.sh
source "$PKGROOT/node.sh"
# shellcheck source=curl-boot-server.sh
source "$PKGROOT/curl-boot-server.sh"
