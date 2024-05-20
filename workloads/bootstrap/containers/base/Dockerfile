FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get -y update; apt-get -y install --no-install-recommends gettext jq yq; rm -rf /var/cache/apt/lists/*
RUN mkdir /var/lib/home-cluster
COPY .upkg /var/lib/home-cluster/.upkg
COPY lib /var/lib/home-cluster/lib
COPY workloads/bootstrap/commands /var/lib/home-cluster/workloads/bootstrap/commands
COPY workloads/bootstrap/assets /var/lib/home-cluster/workloads/bootstrap/assets
COPY home-cluster.yaml /var/lib/home-cluster/home-cluster.yaml
ENV OLD_PATH=$PATH
ENV PATH=/var/lib/home-cluster/workloads/bootstrap/commands:$PATH
ENV PKGROOT=/var/lib/home-cluster
