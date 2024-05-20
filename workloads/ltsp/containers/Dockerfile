FROM debian:bookworm

RUN apt-get update && \
  apt-get install --no-install-recommends -y tftpd-hpa ltsp ipxe nbd-server && \
  rm -rf /var/cache/apt/lists/*

COPY --chmod=755 nbd-server-foreground.sh /usr/local/bin/nbd-server-foreground
RUN mkdir /srv/nbd

RUN ltsp ipxe
COPY ltsp.ipxe /srv/tftp/ltsp/ltsp.ipxe
