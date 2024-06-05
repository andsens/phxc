#!/usr/bin/env bash

apt-get -y update
apt-get -y install --no-install-recommends \
  gettext jq yq wget ca-certificates libdigest-sha-perl
rm -rf /var/cache/apt/lists/*

temp=$(mktemp)
# shellcheck disable=SC2064
trap "rm \"$temp\"" EXIT
wget -qO"$temp" "https://github.com/orbit-online/upkg/releases/download/v0.26.5/upkg-install.tar.gz"
shasum -a 256 -c <(echo "478ea3b01d58e2adf32579c2b1abfb257b24d17464367050e254063e42143b12  $temp")
tar xzC /usr/local -f "$temp"
upkg add -gp docopt-lib-v2.0.1 "https://github.com/andsens/docopt.sh/releases/download/v2.0.1/docopt-lib.sh.tar.gz" 539053da8b3063921b8889dbe752279e3a215d8fa3e2550d6521e094981f26a2
upkg add -g "https://github.com/orbit-online/trap.sh/releases/download/v1.1.1/trap.sh.tar.gz" bdc50e863a44866a6d92c11570d8e255f95d65747128e6f262985452e7359bb4
upkg add -g "https://github.com/orbit-online/records.sh/releases/download/v1.0.0/records.sh.tar.gz" 0469f15f5b689cb29b30f2a3b233c61856eb209fc50c74ef141120bbf70697f1
upkg add -g "https://github.com/orbit-online/path-tools/releases/download/v1.0.0/path-tools.tar.gz" 2ae2a98714aa81e2142b749dac9ecdb61e050e66bf8bd33aef0fccb2ce66c84b
upkg add -g "https://github.com/orbit-online/collections.sh/releases/download/v1.0.0/collections.sh.tar.gz" ca741323c2bd77f547fa9aea41050d85dfc5f1ce3ff42f73b7a12f7c90b9be2e
