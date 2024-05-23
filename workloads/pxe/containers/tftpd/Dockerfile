FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:debian

RUN apt-get update && apt-get install --no-install-recommends -y \
  tftpd-hpa \
  && rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/usr/sbin/in.tftpd", "-L", "-u", "tftp", "-a", ":69", "-s", "/var/lib/tftp"]
