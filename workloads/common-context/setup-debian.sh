#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

apt-get -y update
apt-get -y install --no-install-recommends gettext jq yq wget ca-certificates
rm -rf /var/cache/apt/lists/*


temp=$(mktemp)
# shellcheck disable=SC2064
trap "rm \"$temp\"" EXIT
wget -qO"$temp" "https://github.com/orbit-online/upkg/releases/download/v0.27.0/upkg-install.tar.gz"
sha256sum -c <(echo "a27e0178a6ee420a8cd8273125a139394845049f3d0667c91d63a53b31756dec  $temp")
tar xzC /usr/local -f "$temp"
upkg add -g "https://github.com/orbit-online/records.sh/releases/download/v1.0.2/records.sh.tar.gz" 201977ecc5fc9069d8eff12ba6adc9ce1286ba66c9aeee19184e26185cc6ef63
