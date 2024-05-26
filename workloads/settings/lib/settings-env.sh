#!/usr/bin/env bash
# shellcheck source-path=../..

eval_settings() {
  eval "$(generate_settings "${PKGROOT:?}/settings.yaml")"
}

generate_settings() {
  local settings=$1
  yq -r "$(cat <<'EOS'
    . as $root | paths |
    . as $path | join("_") | ascii_upcase as $var |
    $root | getpath($path) |
    if type == "object" then empty
    else
      if type == "array" then "export \($var)='\(. | join("\n"))'"
      else "export \($var)='\(.)'" end
    end
EOS
  )" "$settings"
}
