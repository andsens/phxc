#!/usr/bin/env bash
# shellcheck source-path=../../

CLUSTER_CONTEXT=$(source "${PKGROOT:?}/vars.sh"; printf "%s\n" "$CLUSTER_CONTEXT")
