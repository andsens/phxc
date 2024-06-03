FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
ARG ARCH
ARG CRI

RUN /workspace/common-context/setup-debian.sh
RUN /workspace/context/run-tasks.sh
