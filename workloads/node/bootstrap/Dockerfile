FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG VARIANT

RUN \
  /workspace/common-context/setup-debian.sh; \
  upkg add -g /workspace/home-cluster.tar.gz; \
  /usr/local/lib/upkg/.upkg/home-cluster/workloads/node/bootstrap/scripts/run-tasks.sh
