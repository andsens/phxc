FROM debian:trixie
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

WORKDIR /registry
RUN /workspace/common-context/setup-debian.sh; \
  apt-get update; apt-get install -y --no-install-recommends \
  python3-venv \
  ; rm -rf /var/cache/apt/lists/*; \
  python3 -m venv /registry; \
  bin/pip3 install -r /workspace/context/requirements.txt; \
  upkg add -g /workspace/common-context/smallstep.upkg.json

ENTRYPOINT ["bin/gunicorn", "-b", "0.0.0.0:8020", "--certfile", "/data/tls/tls.crt", "--keyfile", "/data/tls/tls.key", "--worker-class", "gevent", "--timeout", "0", "registry:gunicorn(root=\"/data\")"]
