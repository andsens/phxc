#!/usr/bin/env bash

initialize_certificates() {
  mkdir -p "${STEPPATH:?}/certs" "$STEPPATH/secrets" "$STEPPATH/config"
  ROOT_CRT=$STEPPATH/certs/root_ca.crt
  ROOT_KEY=$STEPPATH/secrets/root_ca_key
  INTERMEDIATE_CRT=$STEPPATH/certs/intermediate_ca.crt
  INTERMEDIATE_KEY=$STEPPATH/secrets/intermediate_ca_key
  SB_CRT=$STEPPATH/certs/secureboot.crt
  SB_PUBKEY=$STEPPATH/certs/secureboot.pub
  SB_KEY=$STEPPATH/secrets/secureboot_key
  BOOT_SERVER_CRT=$STEPPATH/certs/boot-server.crt
  BOOT_SERVER_KEY=$STEPPATH/certs/boot-server.key
  BOOT_SERVER_BUNDLE=$STEPPATH/certs/boot-server.bundle.crt

  verbose "Setting up/checking root and intermediate certificates"
  if [[ ! -e $ROOT_KEY ]] || \
        ! step certificate lint "$ROOT_CRT" &>/dev/null || \
          step certificate needs-renewal "$ROOT_CRT" &>/dev/null; then
    local root_key_arg=("--key" "$ROOT_KEY")
    [[ -e $ROOT_KEY ]] || root_key_arg=("$ROOT_KEY")
    step certificate create --profile root-ca \
      --force --no-password --insecure \
      --not-after 87600h \
      "home-cluster root" "$ROOT_CRT" "${root_key_arg[@]}" &>/dev/null
  fi

  if [[ ! -e $INTERMEDIATE_KEY ]] || \
        ! step certificate verify "$INTERMEDIATE_CRT" --roots="$ROOT_CRT" &>/dev/null || \
          step certificate needs-renewal "$INTERMEDIATE_CRT" &>/dev/null; then
    local intermediate_key_arg=("--key" "$INTERMEDIATE_KEY")
    [[ -e $INTERMEDIATE_KEY ]] || intermediate_key_arg=("$INTERMEDIATE_KEY")
    step certificate create --profile intermediate-ca \
      --force --no-password --insecure \
      --not-after 87600h \
      --ca "$ROOT_CRT" --ca-key "$ROOT_KEY" \
      home-cluster "$INTERMEDIATE_CRT" "${intermediate_key_arg[@]}" &>/dev/null
  fi

  if [[ ! -e $SB_CRT ]]; then
    # Key *must* be RSA. When sbsign signs the UKI it always specifies that the key is RSA regardless of the facts.
    step certificate create --template <(printf '{
  "subject": {{ toJson .Subject }},
  "keyUsage": ["digitalSignature"],
  "extKeyUsage": ["codeSigning"]
}') --force --insecure --no-password --not-after $((20*365*24))h --kty RSA \
    --ca "$INTERMEDIATE_CRT" --ca-key "$INTERMEDIATE_KEY" \
    "home-cluster Secure Boot" "$SB_CRT" "$SB_KEY"
  fi
  step crypto key public "$SB_KEY" >"$SB_PUBKEY"

  if [[ ! -e $BOOT_SERVER_KEY ]] || \
        ! step certificate verify "$BOOT_SERVER_CRT" --roots="$INTERMEDIATE_CRT" &>/dev/null || \
          step certificate needs-renewal "$BOOT_SERVER_CRT" &>/dev/null; then
    step certificate create \
      --ca "$INTERMEDIATE_CRT" --ca-key "$INTERMEDIATE_KEY" \
      --force --no-password --insecure \
      boot-server.node.svc.cluster.local "$BOOT_SERVER_CRT" "$BOOT_SERVER_KEY"
  fi
  step certificate bundle --force "$BOOT_SERVER_CRT" "$INTERMEDIATE_CRT" "$BOOT_SERVER_BUNDLE"

  jq -n --arg steppath "$STEPPATH" --arg root_fp "$(step certificate fingerprint "$ROOT_CRT")" --arg root_crt "$ROOT_CRT" '{
      "ca-config": "\($steppath)/config/ca.json",
      "fingerprint": $root_fp,
      "root": $root_crt
  }' >"$STEPPATH/config/defaults.json"
  jq -n --arg root_crt "$ROOT_CRT" --arg intermediate_crt "$INTERMEDIATE_CRT" --arg intermediate_key "$INTERMEDIATE_KEY" '{
    "root": $root_crt,
    "crt": $intermediate_crt,
    "key": $intermediate_key
  }' >"$STEPPATH/config/ca.json"
}
