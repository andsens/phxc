FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG ARCH

RUN \
  /workspace/common-context/setup-debian.sh; \
  upkg add -g /workspace/home-cluster.tar.gz; \
  /usr/local/lib/upkg/.upkg/home-cluster/workloads/node/bootstrap/scripts/run-tasks.sh
