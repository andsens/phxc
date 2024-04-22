#!/usr/bin/env bash

get_setting() {
  local path=$1 parent key
  parent=${path%'.'*}
  key=${path##*'.'}
  if yq -re ".$parent | has(\"$key\")" "$PKGROOT/settings.yaml" >/dev/null; then
    yq -re ".$path // empty" "$PKGROOT/settings.yaml"
  else
    printf "Unable to find setting path '%s' in %s" "$path" "$PKGROOT/settings.yaml" >&2
    return 1
  fi
}

query_setting() {
  yq -r "$1" "$PKGROOT/settings.yaml"
}
