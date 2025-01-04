#!/usr/bin/env bash

config() {
  chmod 0755 /usr/local/bin/get-config
  mkdir /etc/phxc
  [[ ! -e /workspace/cluster.json ]] || cp /workspace/cluster.json /etc/phxc/cluster.json
  upkg add -g /usr/local/lib/upkg/.upkg/phxc/lib/common-context/jsonschema-cli.upkg.json
}
