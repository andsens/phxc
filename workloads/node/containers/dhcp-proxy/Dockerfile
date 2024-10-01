FROM alpine
RUN apk add --no-cache bash
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

WORKDIR /dhcp-proxy
RUN /workspace/common-context/setup-alpine.sh; \
  apk add py3-virtualenv; python3 -m venv /dhcp-proxy; \
  bin/pip3 install -r /workspace/context/requirements.txt

ENTRYPOINT ["bin/python3", "dhcp-proxy.py"]
