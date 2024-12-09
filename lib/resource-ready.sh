#!/usr/bin/env bash

check_ready() {
  local wait=false ret
  if [[ $1 = '--wait' ]]; then
    wait=true
    shift
  fi

  # shellcheck disable=SC2154
  if $wait; then
    set +e; (set -e; is_ready &>/dev/null); ret=$?; set -e
    until [[ $ret = 0 ]]; do
      sleep 1
      set +e; (set -e; is_ready &>/dev/null); ret=$?; set -e
    done
    return 0
  else
    is_ready &>/dev/null
  fi
}

crd_installed() {
  local crd=$1
  kubectl get crd "$crd" || return 1
}

deployment_ready() {
  local ns=$1 deployment=$2
  [[ $(kubectl get -n "$ns" deployment "$deployment" -ojsonpath='{.status.readyReplicas}') -gt 0 ]] || return 1
}

statefulset_ready() {
  local ns=$1 sts=$2
  [[ $(kubectl get -n "$ns" statefulset "$sts" -ojsonpath='{.status.readyReplicas}') -gt 0 ]] || return 1
}

pod_ready() {
  local ns=$1 pod=$2
  kubectl -n "$ns" get pod "$pod" -o=jsonpath='{.status.conditions}' | status_is_ready
}

namespace_ready() {
  local ns=$1
  [[ $(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null) = 'Active' ]] || return 1
}

endpoint_ready() {
  local ns=$1 endpoint=$2
  kubectl -n "$ns" get endpoints "$endpoint" -ojsonpath='{.subsets[*].addresses}' | jq -e 'length > 0'
}

status_is_ready() {
  jq -re 'any(.[] | select(.type == "Ready"); .status == "True")' >/dev/null
}

image_ready() {
  local ref=$1
  ctr -n k8s.io image ls -q | grep -q "^$ref$" || return 1
}
