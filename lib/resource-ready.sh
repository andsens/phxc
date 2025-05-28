#!/usr/bin/env bash
# shellcheck source-path=..

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.upkg/records.sh/records.sh"

check_ready() {
  local wait=false ret
  if [[ $1 = '--wait' ]]; then
    wait=true
    shift
  fi

  # shellcheck disable=SC2154
  if $wait; then
    set +e; (set -e; is_ready >/dev/null 2> >(LOGPROGRAM= pipe_verbose)); ret=$?; set -e
    until [[ $ret = 0 ]]; do
      sleep 1
      set +e; (set -e; is_ready >/dev/null 2> >(LOGPROGRAM= pipe_verbose)); ret=$?; set -e
    done
    return 0
  else
    is_ready >/dev/null 2> >(LOGPROGRAM= pipe_verbose)
  fi
}

crd_installed() {
  local crd=$1
  if kubectl get crd "$crd"; then
    verbose "The CRD '%s' is installed" "$crd"
  else
    verbose "The CRD '%s' has not been installed yet" "$crd"
    return 1
  fi
}

deployment_ready() {
  local ns=$1 deployment=$2 count
  count=$(kubectl get -n "$ns" deployment "$deployment" -ojsonpath='{.status.readyReplicas}')
  verbose "The deployment '%s' in '%s' has %d ready replicas" "$deployment" "$ns" "$count"
  [[ $count -gt 0 ]] || return 1
}

statefulset_ready() {
  local ns=$1 sts=$2 count
  count=$(kubectl get -n "$ns" statefulset "$sts" -ojsonpath='{.status.readyReplicas}')
  verbose "The stateful set '%s' in '%s' has %d ready replicas" "$sts" "$ns" "$count"
  [[ $count -gt 0 ]] || return 1
}

pod_ready() {
  local ns=$1 pod=$2
  if kubectl -n "$ns" get pod "$pod" -o=jsonpath='{.status.conditions}' | status_is_ready; then
    verbose "The pod '%s' in '%s' is ready" "$pod" "$ns"
    return 0
  else
    verbose "The pod '%s' in '%s' is not ready" "$pod" "$ns"
    return 1
  fi
}

resource_exists() {
  local resource_type=$1 resource_name=$2
  kubectl get "$resource_type" "$resource_name"
}

resource_phase_is() {
  local namespace resource_type resource_name required_phase phase
  if [[ $1 = namespace ]]; then
    resource_type=$1 resource_name=$2 required_phase=$3
    phase=$(kubectl get "$resource_type" "$resource_name" -o jsonpath='{.status.phase}')
    verbose "The %s '%s' is in the '%s' phase" "$resource_type" "$resource_name" "$phase"
  else
    namespace=$1 resource_type=$2 resource_name=$3 required_phase=$4
    phase=$(kubectl -n "$namespace" get "$resource_type" "$resource_name" -o jsonpath='{.status.phase}')
    verbose "The %s '%s' in '%s' is in the '%s' phase" "$resource_type" "$resource_name" "$namespace" "$phase"
  fi
  [[ $phase = "$required_phase" ]] || return 1
}

endpoint_ready() {
  local ns=$1 endpoint=$2 addrcount
  addrcount=$(kubectl -n "$ns" get endpoints "$endpoint" -ojsonpath='{.subsets[*].addresses}' | jq -re 'length')
  verbose "The endpoint '%s' in '%s' has %d addresses" "$endpoint" "$ns" "$addrcount"
  [[ $addrcount -gt 0 ]] || return 1
}

certificate_ready() {
  local ns=$1 cert=$2
  if kubectl -n "$ns" get certificate "$cert" -o=jsonpath='{.status.conditions}' | status_is_ready; then
    verbose "The certificate '%s' in '%s' is ready" "$cert" "$ns"
    return 0
  else
    verbose "The certificate '%s' in '%s' is not ready" "$cert" "$ns"
    return 1
  fi
}

status_is_ready() {
  jq -re 'any(.[] | select(.type == "Ready"); .status == "True")' >/dev/null
}
