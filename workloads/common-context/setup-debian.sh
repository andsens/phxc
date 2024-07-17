#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

apt-get -y update
apt-get -y install --no-install-recommends gettext jq yq wget ca-certificates
rm -rf /var/cache/apt/lists/*


temp=$(mktemp)
# shellcheck disable=SC2064
trap "rm \"$temp\"" EXIT
wget -qO"$temp" "https://github.com/orbit-online/upkg/releases/download/v0.28.0/upkg-install.tar.gz"
sha256sum -c <(echo "abd498bf0b50dbda1e115546a191c781796b7af4e597f3c3a29ba210c8352ccb  $temp")
tar xzC /usr/local -f "$temp"
upkg_json=$(jq --argjson common "$(cat "$(dirname "${BASH_SOURCE[0]}")/common.upkg.json")" \
  '.dependencies += $common.dependencies' \
  /usr/local/lib/upkg/upkg.json
)
printf "%s\n" "$upkg_json" >/usr/local/lib/upkg/upkg.json
(cd /usr/local/lib/upkg; upkg install)
