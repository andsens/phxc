FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:alpine

RUN apk add nbd
RUN addgroup nbd; adduser -DHG nbd nbd

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/nbd-server-foreground.sh"]
