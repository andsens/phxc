FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  gettext jq yq \
  ; rm -rf /var/cache/apt/lists/*
