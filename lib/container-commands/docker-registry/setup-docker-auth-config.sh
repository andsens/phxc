#!/usr/bin/env bash
# shellcheck source-path=../../..
# shellcheck disable=SC2016
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
apk add -q --update --no-cache jq kubectl gettext whois py3-virtualenv apache2-utils
virtualenv -q /usr/local/lib/yq
/usr/local/lib/yq/bin/pip3 install yq
ln -s /usr/local/lib/yq/bin/yq /usr/local/bin/yq

source "$PKGROOT/lib/common.sh"

main() {
  mkdir -p /config/certs
  info "Hashing k3s registry credentials"
  local k3s_username k3s_password
  k3s_username=$(yq -re '.configs["distribution.docker-registry.svc.cluster.local"].auth.username' /etc/rancher/k3s/registries.yaml)
  k3s_password=$(yq -re '.configs["distribution.docker-registry.svc.cluster.local"].auth.password' /etc/rancher/k3s/registries.yaml | htpasswd -nBi "")
  k3s_password=${k3s_password#:}

  info "Hashing kaniko registry credentials"
  local kaniko_password
  kaniko_username=$(cat /kaniko-credentials/username)
  kaniko_password=$(htpasswd -nbB "" "$(cat kaniko-credentials/password)")
  kaniko_password=${kaniko_password#:}

  info "Replacing variables in auth.yaml"
  K3S_USERNAME=$k3s_username K3S_PASSWORD=$k3s_password \
  KANIKO_USERNAME=$kaniko_username KANIKO_PASSWORD=$kaniko_password \
  envsubst '$K3S_USERNAME $K3S_PASSWORD $KANIKO_USERNAME $KANIKO_PASSWORD' \
    </var/lib/home-cluster/config/docker/auth.yaml >/config/auth_config.yml
}

main "$@"
