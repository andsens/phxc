FROM alpine
RUN apk add --no-cache bash
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]
RUN /workspace/common-context/setup-alpine.sh; \
  apk add tcpdump tftp-hpa; adduser -DH tftp; adduser -DH tcpdump; mkdir /tftp
ENTRYPOINT ["/tftpd.sh"]
