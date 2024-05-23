FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:debian

RUN apt-get update && \
  apt-get install --no-install-recommends -y tftpd-hpa \
  && rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/nbd-server-foreground.sh"]
