#!/bin/sh
set -e
apk add --update --no-cache bash jq kubectl gettext mkpasswd py3-pip gettext
python3 -m venv /pyenv
/pyenv/bin/pip install yq
ln -s /pyenv/bin/yq /usr/local/bin/yq

exec /var/lib/home-cluster/lib/container-commands/docker-registry/init-docker-auth.bash "$@"
