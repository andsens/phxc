FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:alpine

RUN apk add tftp-hpa perl-utils; adduser -DH tftp; mkdir /tftp; \
  wget -qO/tftp/ipxe.efi http://boot.ipxe.org/ipxe.efi; \
  shasum -a 256 -c <(echo '89c58b5967969ad2e414c0c7479b1ccbc53ae5b44d46c55919b7ab051a44aae8  /tftp/ipxe.efi')

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/tftpd.sh"]
