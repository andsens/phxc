#!/bin/sh
set -e
apk add --update --no-cache bash jq kubectl

mkdir -p /usr/local/bin
wget -qO- https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.26.1/step_linux_0.26.1_amd64.tar.gz | \
  tar -xzC /usr/local/bin --strip-components 2 step_0.26.1/bin/step
chmod +x /usr/local/bin/step
mkdir /certs
kubectl get -n smallstep secret kube-apiserver-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d >/certs/kube_apiserver_client_ca.crt

exec /docker_auth/auth_server "$@"
