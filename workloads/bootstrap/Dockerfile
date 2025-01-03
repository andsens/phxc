FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG VARIANT
ARG DEBUG=false

RUN printf 'Acquire::http { Proxy "http://apt-cacher-ng.phxc.svc.cluster.local:3142"; }\n' >/etc/apt/apt.conf.d/20apt-cacher-ng.conf; \
  apt-get -y update; apt-get -y install --no-install-recommends \
  jq wget ca-certificates \
  ; temp=$(mktemp); \
  wget -qO"$temp" "https://github.com/orbit-online/upkg/releases/download/v0.28.2/upkg-install.tar.gz"; \
  sha256sum -c <(echo "4a2956232b059b11395b9d575a817233a67a56528217a576e9016cbaa62f007c  $temp"); \
  tar xzC /usr/local -f "$temp"; \
  upkg add -g /workspace/phxc.tar.gz; \
  /usr/local/lib/upkg/.upkg/phxc/bootstrap/scripts/run-tasks.sh
