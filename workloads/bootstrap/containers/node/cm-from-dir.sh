#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  local input name path cm
  input=$(cat)
  name=$(yq -r .functionConfig.spec.name <<<"$input")
  path=$(yq -r .functionConfig.spec.path <<<"$input")
  # shellcheck disable=SC2016
  cm=$(yq --arg name "$name" '.items[0].metadata.name=$name' <<<'kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
  data:
')
  local file key
  while IFS= read -r -d $'\0' file; do
    key=${file#"$path"/}
    key=${key//'/'/'$'}
    # shellcheck disable=SC2016
    cm=$(yq -y --indentless --arg key "$key" --arg file "$(cat "$file")" '.items[0].data[$key]=$file' <<<"$cm")
  done < <(find "$path" -type f -print0)
  printf "%s\n" "$cm"
}

main "$@"
