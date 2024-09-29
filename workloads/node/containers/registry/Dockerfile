FROM debian:trixie
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

WORKDIR /boot-server-registry
RUN /workspace/common-context/setup-debian.sh; \
  apt-get update; apt-get install -y --no-install-recommends \
  python3-venv \
  ; rm -rf /var/cache/apt/lists/*; \
  python3 -m venv /boot-server-registry; \
  bin/pip3 install -r /workspace/context/requirements.txt

ENTRYPOINT ["bin/gunicorn", "-b", "127.0.0.1:8000", "attest-server:app"]
