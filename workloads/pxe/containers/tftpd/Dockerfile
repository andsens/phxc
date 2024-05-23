FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:debian

RUN apk add tftpd-hpa

ENTRYPOINT ["/usr/sbin/in.tftpd", "-L", "-u", "tftp", "-a", ":69", "-s", "/images/kernels"]
