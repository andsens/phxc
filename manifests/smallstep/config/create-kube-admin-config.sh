#!/bin/bash
set -Eeo pipefail; shopt -s inherit_errexit

: "${STEPPATH:?}" "${NAMESPACE:?}" "${K8S_API_HOST:?}" "${KUBE_CONFIG_OWNER:?}"
ROOT_CRT_PATH=$STEPPATH/persistent-certs/root_ca.crt
KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/persistent-certs/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/persistent-certs/kube_apiserver_client_ca.crt
KUBE_ADMIN_KEY_PATH=$STEPPATH/persistent-certs/system:admin_key
KUBE_ADMIN_CRT_PATH=$STEPPATH/persistent-certs/system:admin.crt
KUBE_ADMIN_CONFIG_PATH=$STEPPATH/persistent-certs/home-cluster.yaml
NEW_KUBE_ADMIN_CONFIG_PATH=$STEPPATH/certs/home-cluster.yaml

main() {
  info "Creating kube admin client cert and kube admin config"

  if [[ ! -e $KUBE_ADMIN_KEY_PATH ]] || \
        ! step certificate verify "$KUBE_ADMIN_CRT_PATH" --roots="$ROOT_CRT_PATH,$KUBE_CLIENT_CA_CRT_PATH" || \
          step certificate needs-renewal "$KUBE_ADMIN_CRT_PATH"; then
    info "Kube admin client cert validation failed, (re-)creating now"
    step certificate create --template=<(printf '{
      "subject": {
        "commonName": {{ toJson .Subject.CommonName }},
        "extraNames": [{"type":"2.5.4.10", "value": "system:masters"}]
      },
      "keyUsage": ["keyEncipherment", "digitalSignature"],
      "extKeyUsage": ["clientAuth"]}') \
      --no-password --insecure \
      --force \
      --not-after=24h \
      --ca="$KUBE_CLIENT_CA_CRT_PATH" --ca-key="$KUBE_CLIENT_CA_KEY_PATH" \
      "system:admin" "$KUBE_ADMIN_CRT_PATH" "$KUBE_ADMIN_KEY_PATH"
  else
    info "Kube admin client cert validation succeeded"
  fi

  kubectl config --kubeconfig "$NEW_KUBE_ADMIN_CONFIG_PATH" set-cluster home-cluster \
    --embed-certs \
    --server="https://$K8S_API_HOST:6443" \
    --certificate-authority="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  kubectl config --kubeconfig "$NEW_KUBE_ADMIN_CONFIG_PATH" set-credentials admin@home-cluster \
    --embed-certs \
    --client-certificate="$KUBE_ADMIN_CRT_PATH" \
    --client-key="$KUBE_ADMIN_KEY_PATH"
  kubectl config --kubeconfig "$NEW_KUBE_ADMIN_CONFIG_PATH" set-context home-cluster \
    --cluster home-cluster --user admin@home-cluster
  kubectl config --kubeconfig "$NEW_KUBE_ADMIN_CONFIG_PATH" use-context home-cluster

  if [[ ! -e "$KUBE_ADMIN_CONFIG_PATH" ]] || ! diff -q "$NEW_KUBE_ADMIN_CONFIG_PATH" "$KUBE_ADMIN_CONFIG_PATH"; then
    info "Kube admin config validation failed, (re-)creating now"
    mv "$NEW_KUBE_ADMIN_CONFIG_PATH" "$KUBE_ADMIN_CONFIG_PATH"
  else
    info "Kube admin config validation succeeded"
  fi

  info "Setting owner of kube config to %s:%s" "$KUBE_CONFIG_OWNER" "$KUBE_CONFIG_OWNER"
  chown "$KUBE_CONFIG_OWNER:$KUBE_CONFIG_OWNER" "$KUBE_ADMIN_CONFIG_PATH"
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "%s: $tpl\n" "$(basename "$0")" "$@" >&2
}

main "$@"
