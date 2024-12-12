FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG VARIANT
ARG DEBUG=false

RUN \
  /workspace/common-context/setup-debian.sh; \
  upkg add -g /workspace/phoenix-cluster.tar.gz; \
  /usr/local/lib/upkg/.upkg/phoenix-cluster/bootstrap/scripts/run-tasks.sh
