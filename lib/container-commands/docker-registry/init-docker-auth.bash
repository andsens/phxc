#!/bin/bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
source "$PKGROOT/lib/common.sh"

main() {
  mkdir -p /usr/local/bin
  wget -qO- https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.26.1/step_linux_0.26.1_amd64.tar.gz | \
    tar -xzC /usr/local/bin --strip-components 2 step_0.26.1/bin/step
  chmod +x /usr/local/bin/step
  mkdir /certs
  kubectl get -n smallstep secret kube-apiserver-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d >/certs/kube_apiserver_client_ca.crt

  local k3s_username k3s_password
  # shellcheck disable=SC2016
  read -r k3s_username k3s_password < <(\
    yq -r --arg domain "$(get_setting cluster.domain)" '.configs["cr.\($domain)"] | (.username, .password)' /etc/rancher/k3s/registries.yaml \
  )
  # shellcheck disable=SC2016
  K3S_USERNAME=$k3s_username K3S_PASSWORD=$(printf "%s" "$k3s_password" | mkpasswd --stdin) envsubst '$K3S_USERNAME $K3S_PASSWORD' \
    </var/lib/home-cluster/config/docker/auth.yaml >/config/auth_config.yml

  exec /docker_auth/auth_server "$@"
}

main "$@"
