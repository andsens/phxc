FROM alpine
RUN apk add bash gettext jq kubectl py3-virtualenv
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN /workspace/common-context/setup-alpine.sh

RUN apk add nginx; upkg -g add /workspace/settings-context/generate-node-settings.sh
ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/boot-server.sh"]
