#!/usr/bin/env bash

utils_pre_copy() {
  FILES_ENVSUBST+=(
    /etc/systemd/system.conf.d/debug.conf
    /etc/systemd/system.conf.d/disk-uuids.conf
    /etc/systemd/system.conf.d/efi-arch.conf
    /etc/systemd/system.conf.d/variant.conf
  )
}

utils() {
  upkg add -g /usr/local/lib/upkg/.upkg/phxc/lib/common-context/jsonschema-cli.upkg.json
  if [[ $VARIANT != rpi* ]]; then
    upkg add -g \
      'https://github.com/andsens/cryptenroll-uki/releases/download/v0.0.3/cryptenroll-uki.tar.gz' \
      83d61b73728e9bd815527ab19fab28ccd815e1555ba8410dd437ec08fa8b72d3
    upkg add -g \
      'https://github.com/orbit-online/efi-bootentry/releases/download/v0.0.3/efi-bootentry.tar.gz' \
      eef8541b0148b32ed341c379aefe06e8364121129b7864d46209ccd473b8a25c
  fi
}
