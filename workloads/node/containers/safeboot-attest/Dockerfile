FROM debian:bookworm
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

WORKDIR /usr/local/lib/safeboot-attest
RUN /workspace/common-context/setup-debian.sh; \
  apt-get update; apt-get install -y --no-install-recommends \
  python3-venv tpm2-tools xxd \
  ; rm -rf /var/cache/apt/lists/*; \
  python3 -m venv /usr/local/lib/safeboot-attest; \
  bin/pip3 install -r /workspace/context/requirements.txt ;\
  upkg add -gp kubectl https://dl.k8s.io/release/v1.30.1/bin/linux/amd64/kubectl 5b86f0b06e1a5ba6f8f00e2b01e8ed39407729c4990aeda961f83a586f975e8a

ENTRYPOINT ["bin/gunicorn", "-b", "127.0.0.1:8000", "attest-server:app"]
