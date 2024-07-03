#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

apk add jq gettext py3-virtualenv
virtualenv /usr/local/lib/yq
/usr/local/lib/yq/bin/pip3 install yq
ln -s /usr/local/lib/yq/bin/yq /usr/local/bin/yq

temp=$(mktemp)
# shellcheck disable=SC2064
trap "rm \"$temp\"" EXIT
wget -qO"$temp" "https://github.com/orbit-online/upkg/releases/download/v0.27.0/upkg-install.tar.gz"
sha256sum -c <(echo "a27e0178a6ee420a8cd8273125a139394845049f3d0667c91d63a53b31756dec  $temp")
tar xzC /usr/local -f "$temp"
upkg_json=$(jq --argjson common "$(cat "$(dirname "${BASH_SOURCE[0]}")/common.upkg.json")" \
  '.dependencies += $common.dependencies' \
  /usr/local/lib/upkg/upkg.json
)
printf "%s\n" "$upkg_json" >/usr/local/lib/upkg/upkg.json
(cd /usr/local/lib/upkg; upkg install)
