FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:debian as pxe-donor

RUN apt-get update && apt-get install --no-install-recommends -y \
  ipxe \
  && rm -rf /var/cache/apt/lists/*

FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:alpine

RUN apk add tftp-hpa; mkdir -p /tftp/pxe; adduser -DH tftp
COPY --from=pxe-donor /usr/lib/ipxe/snponly.efi /usr/lib/ipxe/undionly.kpxe /tftp/pxe

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/tftpd.sh"]
