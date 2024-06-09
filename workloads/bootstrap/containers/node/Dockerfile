FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG ARCH
ARG CRI

RUN \
  /workspace/common-context/setup-debian.sh ;\
  upkg add -g /workspace/context/home-cluster.tar.gz ;\
  /usr/local/lib/upkg/.upkg/home-cluster/workloads/bootstrap/containers/node/scripts/run-tasks.sh
