FROM alpine
RUN apk add --no-cache bash
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN /workspace/common-context/setup-alpine.sh; \
  apk add py3-virtualenv; python3 -m venv /venv; \
  /venv/bin/pip3 install -r /workspace/context/requirements.txt

ENTRYPOINT ["/boot-server/boot-server.sh"]
