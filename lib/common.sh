#!/usr/bin/env bash
# shellcheck source-path=..

# shellcheck disable=SC2034
STEP_KUBE_API_CONTEXT=home-cluster-kube-api
STEP_PKI_CONTEXT=home-cluster-pki
KUBE_CONTEXT=home-cluster
KUBE_CLUSTER=home-cluster
DOCKER_CRED_HELPER=home-cluster
export DOCKER_CLI_HINTS=false

PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

# shellcheck disable=SC1091
source "$PKGROOT/.upkg/records.sh/records.sh"
# shellcheck disable=SC1091
source "$PKGROOT/.upkg/collections.sh/collections.sh"
# shellcheck disable=SC1091
source "$PKGROOT/.upkg/trap.sh/trap.sh"
# shellcheck source=workloads/settings/lib/settings-env.shellcheck.sh
source "$PKGROOT/workloads/settings/lib/settings-env.sh"
eval_settings
