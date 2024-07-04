#!/usr/bin/env bash

PACKAGES+=(
  make gcc libclang-dev libssl-dev libtss2-dev libzmq3-dev pkg-config # build deps
  libssl3 libtss2-esys-3.0.2-0 tpm2-abrmd # runtime deps
)

keylime() {
  wget -qO- https://sh.rustup.rs | bash -s -- -qy
  PATH=$HOME/.cargo/bin:$PATH
  local \
    src \
    src_url=https://github.com/keylime/rust-keylime/archive/refs/tags/v0.2.6.tar.gz \
    src_sha256=14a1520c2760d070f955c6d59a731174f350e642cfbd6e87bfefbe3b3b08f6cc
  src=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf \"$src\"" EXIT
  wget -qO"$src/src.tar.gz" "$src_url"
  printf "%s  %s\n" "$src_sha256" "$src/src.tar.gz" | sha256sum -c -
  tar -xzf "$src/src.tar.gz" -C "$src" --strip-components=1
  cargo install cargo-deb
  # shellcheck disable=SC2164
  (cd "$src"; cargo deb -p keylime_agent)
  dpkg -i "$src/target/debian/keylime-agent_0.2.6-1_amd64.deb"
  cp_tpl /etc/keylime/agent.conf
  rustup self uninstall -y
  apt-get purge -qy make gcc libclang-dev libssl-dev libtss2-dev libzmq3-dev pkg-config
}
