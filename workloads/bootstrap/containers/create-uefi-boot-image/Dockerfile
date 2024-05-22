FROM debian:bookworm
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  gettext jq yq \
  fdisk uuid-runtime e2fsprogs dosfstools systemd-boot udev zerofree \
  ; rm -rf /var/cache/apt/lists/*

ENTRYPOINT ["/var/lib/home-cluster/workloads/bootstrap/commands/create-uefi-boot-image.sh"]
