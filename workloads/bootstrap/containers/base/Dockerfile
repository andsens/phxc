FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG MACHINE
RUN apt-get -y update; apt-get -y install --no-install-recommends gettext jq yq; rm -rf /var/cache/apt/lists/*
ENV OLD_PATH=$PATH
ENV PATH=/workspace/workloads/bootstrap/commands:$PATH
ENV PKGROOT=/workspace
