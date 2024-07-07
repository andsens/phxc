FROM alpine
RUN apk add --no-cache bash
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]
RUN /workspace/common-context/setup-alpine.sh; \
  apk add tftp-hpa perl-utils; adduser -DH tftp; mkdir /tftp
ENTRYPOINT ["/usr/sbin/in.tftpd", \
  "--foreground", \
  "--user", "tftp", \
  "--address", ":69", \
  "--map-file", "/config/map-file", \
  "--secure", "/tftp", \
  "--blocksize", "1468" \
]
