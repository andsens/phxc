FROM alpine
RUN apk add bash gettext jq kubectl py3-virtualenv
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apk add jq py3-virtualenv; \
  virtualenv /usr/local/lib/yq; \
  /usr/local/lib/yq/bin/pip3 install yq; \
  ln -s /usr/local/lib/yq/bin/yq /usr/local/bin/yq
