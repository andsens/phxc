#!/usr/bin/env bash
# shellcheck source-path=../..

eval_settings() {
  local settings_path=${1:-"${PKGROOT:?}/settings.yaml"} settings
  settings=$(generate_settings "$settings_path")
  eval "$settings"
}

generate_settings() {
  local settings_path=$1 script
  script=$(cat <<'EOS'
    . as $root | paths |
    . as $path | join("_") | gsub("-"; "_") | ascii_upcase as $var |
    $root | getpath($path) |
    if type == "object" or type == "array" then empty
    else
      "export \($var)='\(.)'"
    end
EOS
  )
  yq -r "$script" "$settings_path"
}
