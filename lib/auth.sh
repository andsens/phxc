#!/usr/bin/env bash
# shellcheck source-path=..

extract_kube_config_to_smallstep() {
  local step_profile=$1 kube_config_path=$2 crt username cert_path
  crt=$(yq -r '.users[] | .user["client-certificate-data"]' "$kube_config_path" | base64 -d)
  username=$(step certificate inspect <(printf "%s" "$crt") --format json | jq -r '.subject.common_name[0]')

  cert_path=$(get_smallstep_certs_path "$step_profile")
  info "Writing client cert & key to %s" "$cert_path"
  (
    umask 077
    mkdir -p "$cert_path"
     printf "%s\n" "$crt" >"$cert_path/$username.crt"
    yq -r '.users[] | .user["client-key-data"]' "$kube_config_path" | base64 -d >"$cert_path/${username}_key"
  )
  set_smallstep_x5c_cert_path "$step_profile" "$cert_path/$username.crt"
  set_smallstep_x5c_key_path "$step_profile" "$cert_path/${username}_key"
}

setup_kube_config() {
  local step_profile=$1 kube_context=$2 kube_cluster=$3 kube_config_path username
  kube_config_path=$(get_kube_config_path "$kube_context")
  mkdir -p "$(dirname "$kube_config_path")"
  username=$(get_kube_username "$step_profile")
  info "Setting up kubernetes config"
  kubectl config --kubeconfig "$kube_config_path" set-credentials "$username@$kube_cluster" \
    --client-certificate="$(get_kube_crt_path "$step_profile")" \
    --client-key="$(get_kube_key_path "$step_profile")"
  kubectl config --kubeconfig "$kube_config_path" set-context "$kube_context" \
    --cluster "$kube_cluster" --user "$username@$kube_cluster"
  export KUBECONFIG="$kube_config_path:$KUBECONFIG"
  if ! kubectl --context "$kube_context" get -n default pods >/dev/null; then
    fatal "Unable to authenticate to the cluster, kube config setup failed"
  fi
}

setup_smallstep_context() {
  local step_context=$1 kube_context=$2 ca_url=$3 root_secret_ns=$4 root_secret_name=$5
  info "Bootstrapping Smallstep %s context" "$step_context"
  step ca bootstrap --context "$step_context" --force --ca-url "$ca_url" \
    --fingerprint "$(step certificate fingerprint <(\
      kubectl --context "$kube_context" -n "$root_secret_ns" get secret "$root_secret_name" -o=jsonpath='{.data.tls\.crt}' | base64 -d))"
}

setup_docker_cred_helper() {
  local cr=$1 helper=$2 docker_config_path=$3 docker_config
  mkdir -p "$(dirname "$docker_config_path")"
  docker_config={}
  [[ ! -e $docker_config_path ]] || docker_config=$(cat "$docker_config_path")
  docker_config=$(jq --arg cr "$cr" --arg helper "$helper" '.auths[$cr]={} | .credHelpers[$cr]=$helper' <<<"$docker_config")
  printf "%s\n" "$docker_config" >"$docker_config_path"
}

setup_ssh_host_cert_trust() {
  local step_profile=$1 hosts=$2 known_hosts_path=$3
  info "Trusting SSH host keys signed by Smallstep"
  # `step ssh config` doesn't work right with --context or --profile
  step context select "$step_profile"
  local expected_known_hosts_line current_known_hosts_line
  expected_known_hosts_line="@cert-authority $hosts $(step ssh config --host --roots)"
  if [[ -e "$known_hosts_path" ]] && current_known_hosts_line=$(grep -F "@cert-authority $hosts " "$known_hosts_path"); then
    if [[ $current_known_hosts_line != "$expected_known_hosts_line" ]]; then
      warning "Replacing '@cert-authority $hosts' line in %s, it does not match the current key" "$known_hosts_path"
      local all_other_lines
      all_other_lines=$(grep -vF "@cert-authority $hosts " "$known_hosts_path")
      printf "%s\n%s\n" "$all_other_lines" "$expected_known_hosts_line" >"$known_hosts_path"
    else
      info "The '@cert-authority $hosts' line in %s exists and is correct" "$known_hosts_path"
    fi
  else
    mkdir -p "$known_hosts_path"
    info "Appending '@cert-authority $hosts ...' to %s" "$known_hosts_path"
    printf "@cert-authority $hosts %s\n" "$expected_known_hosts_line" >>"$known_hosts_path"
  fi
}

sign_ssh_client_keys() {
  local step_context=$1 principal=$2 pubkey
  info "Signing all pubkeys in %s" "$HOME/.ssh"
  for pubkey in "$HOME/.ssh"/id_*.pub; do
    [[ $pubkey != *-cert.pub ]] || continue
    step ssh certificate --context "$step_context" --force --sign "$principal" "$pubkey"
  done
}

get_kube_config_path() {
  local kube_context=$1
  printf "%s/.kube/%s.yaml" "$HOME" "$kube_context"
}

get_kube_crt_path() {
  local step_profile=$1 step_path
  step_path=$(step path --profile "$step_profile")
  jq -r '.["x5c-cert"]' "$step_path/config/defaults.json"
}

get_kube_key_path() {
  local step_profile=$1 step_path
  step_path=$(step path --profile "$step_profile")
  jq -r '.["x5c-key"]' "$step_path/config/defaults.json"
}

get_kube_username() {
  local step_profile=$1
  step certificate inspect "$(get_kube_crt_path "$step_profile")" --format json | jq -r '.subject.common_name[0]'
}

get_smallstep_certs_path() {
  local step_context=$1
  printf "%s/authorities/%s/certs" "${STEPPATH:-$(step path --base)}" "$step_context"
}

set_smallstep_x5c_cert_path() {
  local step_profile=$1 cert_path=$2 config_path
  config_path=$(step path --profile "$step_profile")/config/defaults.json
  jq --arg path "$cert_path" '.["x5c-cert"] = $path' <"$config_path" | sponge "$config_path"
}

set_smallstep_x5c_key_path() {
  local step_profile=$1 key_path=$2 config_path
  config_path=$(step path --profile "$step_profile")/config/defaults.json
  jq --arg path "$key_path" '.["x5c-key"] = $path' <"$config_path" | sponge "$config_path"
}
