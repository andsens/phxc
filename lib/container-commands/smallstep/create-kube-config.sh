#!/bin/bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
apk add jq py3-pip
pip install -q yq
source "$PKGROOT/lib/common.sh"
source "$PKGROOT/lib/container-commands/smallstep/paths.sh"

main() {
  local username=${1:?}; shift; local groups=("$@")
  local \
    key_path=$STEPPATH/persistent-certs/${username}_key \
    crt_path=$STEPPATH/persistent-certs/${username}.crt \
    kube_config_path=$STEPPATH/persistent-certs/home-cluster.yaml \
    new_kube_config_path=$STEPPATH/certs/home-cluster.yaml

  local extra_names='[]' group
  for group in "${groups[@]}"; do
    extra_names=$(jq --arg group "$group" '.+=[{"type":"2.5.4.10", "value": $group}]' <<<"$extra_names")
  done
  local template='{
    "subject": {
      "commonName": {{ toJson .Subject.CommonName }},
      "extraNames": '$extra_names'
    },
    "keyUsage": ["keyEncipherment", "digitalSignature"],
    "extKeyUsage": ["clientAuth"]}'

  info "Creating kube config for user '%s'" "$username"

  if [[ ! -e $key_path ]] || \
        ! step certificate verify "$crt_path" --roots="$KUBE_CLIENT_CA_CRT_PATH" || \
          step certificate needs-renewal "$crt_path"; then
    info "Kube admin client cert validation failed, (re-)creating now"
    step certificate create --template=<(printf "%s\n" "$template") \
      --no-password --insecure \
      --force \
      --not-after=24h \
      --ca="$KUBE_CLIENT_CA_CRT_PATH" --ca-key="$KUBE_CLIENT_CA_KEY_PATH" \
      "$username" "$crt_path" "$key_path"
  else
    info "Kube admin client cert validation succeeded"
  fi

  kubectl config --kubeconfig "$new_kube_config_path" set-cluster $KUBE_CLUSTER \
    --embed-certs \
    --server="https://pki.$(get_setting machines.k8sMaster.hostname):6443" \
    --certificate-authority="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  kubectl config --kubeconfig "$new_kube_config_path" set-credentials "$username@$KUBE_CLUSTER" \
    --embed-certs \
    --client-certificate="$crt_path" \
    --client-key="$key_path"
  kubectl config --kubeconfig "$new_kube_config_path" set-context $KUBE_CONTEXT \
    --cluster $KUBE_CLUSTER --user "$username@$KUBE_CLUSTER"
  kubectl config --kubeconfig "$new_kube_config_path" use-context $KUBE_CONTEXT

  if [[ ! -e "$kube_config_path" ]] || ! diff -q "$new_kube_config_path" "$kube_config_path"; then
    info "Kube admin config validation failed, (re-)creating now"
    mv "$new_kube_config_path" "$kube_config_path"
  else
    info "Kube admin config validation succeeded"
  fi

  local admin_uid
  admin_uid=$(get_setting admin.uid)
  info "Setting owner of kube config to %s:%s" "$admin_uid" "$admin_uid"
  chown "$admin_uid:$admin_uid" "$kube_config_path"
}

main "$@"
