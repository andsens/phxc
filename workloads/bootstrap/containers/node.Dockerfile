FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

ARG ARCH
RUN /workspace/workloads/bootstrap/commands/apply-layers.sh
