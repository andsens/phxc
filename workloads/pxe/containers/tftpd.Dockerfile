FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:alpine

RUN apk add tftp-hpa perl-utils; adduser -DH tftp; mkdir /tftp; \
  wget -qO/tftp/ipxe.efi http://boot.ipxe.org/ipxe.efi; \
  shasum -a 256 -c <(echo '89c58b5967969ad2e414c0c7479b1ccbc53ae5b44d46c55919b7ab051a44aae8  /tftp/ipxe.efi'); \
  wget -qO/tftp/snponly.efi http://boot.ipxe.org/snponly.efi; \
  shasum -a 256 -c <(echo 'a31cc9f9bf4ed12503036650e896688c53e150f9a6f890a15608c2fb13077155  /tftp/snponly.efi'); \
  wget -qO/tftp/undionly.efi http://boot.ipxe.org/undionly.efi; \
  shasum -a 256 -c <(echo '24d303cf88c32167253deb6a12580b9bbb04d695bce08ba4933380f7435e30ff  /tftp/undionly.efi')

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/tftpd.sh"]
