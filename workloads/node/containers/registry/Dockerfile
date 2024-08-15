FROM debian:trixie
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

WORKDIR /safeboot-attest
RUN /workspace/common-context/setup-debian.sh; \
  apt-get update; apt-get install -y --no-install-recommends \
  python3-venv tpm2-tools xxd \
  ; rm -rf /var/cache/apt/lists/*; \
  python3 -m venv /safeboot-attest; \
  bin/pip3 install -r /workspace/context/requirements.txt ;\
  upkg add -g /workspace/common-context/kubectl.upkg.json

ENTRYPOINT ["bin/gunicorn", "-b", "127.0.0.1:8000", "attest-server:app"]
