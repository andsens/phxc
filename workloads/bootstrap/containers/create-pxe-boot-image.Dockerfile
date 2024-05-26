FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:debian

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  squashfs-tools ipxe \
  ; rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/var/lib/home-cluster/workloads/bootstrap/commands/create-pxe-boot-image.sh"]
