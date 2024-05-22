#!/usr/bin/env bash
# shellcheck source-path=..

eval_settings() {
  eval "$(generate_settings)"
  [[ -z $MACHINE ]] || alias_machine "$MACHINE"
}

alias_machine() {
  local machine=$1 key
  for key in $(env | cut -d = -f 1 | grep "^MACHINES_${machine^^}_"); do
    eval "export ${key/#"MACHINES_${machine^^}"/MACHINE}='${!key}'"
  done
}

generate_shellcheck_settings() {
  printf "#!/usr/bin/env bash\n# shellcheck disable=SC2016\n%s" "$(generate_settings)" >"${PKGROOT:?}/lib/settings.shellcheck.sh"
}

generate_settings() {
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
  )" "${PKGROOT:?}/settings.yaml"
}

if [[ ${#BASH_SOURCE[@]} -gt 1 ]]; then
  eval_settings
else
  PKGROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
  generate_shellcheck_settings
fi
