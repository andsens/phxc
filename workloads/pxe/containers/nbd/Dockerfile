FROM debian:bookworm

RUN apt-get update && \
  apt-get install --no-install-recommends -y tftpd-hpa \
  && rm -rf /var/cache/apt/lists/*

RUN mkdir /images

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/nbd-server-foreground.sh"]
