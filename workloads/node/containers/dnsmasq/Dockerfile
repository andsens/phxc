FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]
RUN /workspace/common-context/setup-debian.sh; \
  apt-get -y update; apt-get -y install --no-install-recommends \
  dnsmasq iproute2 subnetcalc \
  ; rm -rf /var/cache/apt/lists/*
ENTRYPOINT ["/dnsmasq.sh"]
