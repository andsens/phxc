FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:debian

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  fdisk uuid-runtime e2fsprogs dosfstools systemd-boot udev qemu-utils zerofree \
  ; rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/var/lib/home-cluster/workloads/bootstrap/commands/create-uefi-boot-image.sh"]
