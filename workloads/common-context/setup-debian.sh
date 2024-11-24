#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

apt-get -y update
apt-get -y install --no-install-recommends jq wget ca-certificates
rm -rf /var/cache/apt/lists/*


temp=$(mktemp)
# shellcheck disable=SC2064
trap "rm \"$temp\"" EXIT
wget -qO"$temp" "https://github.com/orbit-online/upkg/releases/download/v0.28.2/upkg-install.tar.gz"
sha256sum -c <(echo "4a2956232b059b11395b9d575a817233a67a56528217a576e9016cbaa62f007c  $temp")
tar xzC /usr/local -f "$temp"
upkg_json=$(jq --argjson common "$(cat "$(dirname "${BASH_SOURCE[0]}")/common.upkg.json")" \
  '.dependencies += $common.dependencies' \
  /usr/local/lib/upkg/upkg.json
)
printf "%s\n" "$upkg_json" >/usr/local/lib/upkg/upkg.json
(cd /usr/local/lib/upkg; upkg install)
