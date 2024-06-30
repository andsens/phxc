FROM debian:bookworm
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN /workspace/common-context/setup-debian.sh

RUN apt-get -y update; apt-get -y install --no-install-recommends tftpd-hpa shim-signed; rm -rf /var/cache/apt/lists/*; \
  mkdir /tftp; cp /usr/lib/shim/shimx64.efi.signed /tftp/shim.efi; cp /usr/lib/shim/mmx64.efi.signed /tftp/mmx64.efi
ENTRYPOINT ["/usr/sbin/in.tftpd", \
  "--foreground", \
  "--user", "tftp", \
  "--address", ":69", \
  "--map-file", "/config/map-file", \
  "--secure", "/tftp", \
  "--blocksize", "1468" \
]
