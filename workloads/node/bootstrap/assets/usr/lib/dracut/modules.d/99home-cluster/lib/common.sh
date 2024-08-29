#!/usr/bin/env bash

# shellcheck source=../../../../../../../../../../.upkg/records.sh/records.sh
source /usr/lib/home-cluster/records.sh
# shellcheck source=../../../../../../../../../../.upkg/trap.sh/trap.sh
source /usr/lib/home-cluster/trap.sh
# shellcheck disable=SC2034
[[ ${debug:-n} != y ]] || LOGLEVEL=debug
# shellcheck source=node.sh
source /usr/lib/home-cluster/node.sh
# shellcheck source=curl-boot-server.sh
source /usr/lib/home-cluster/curl-boot-server.sh
# shellcheck source=disk-uuids.sh
source /usr/lib/home-cluster/disk-uuids.sh
