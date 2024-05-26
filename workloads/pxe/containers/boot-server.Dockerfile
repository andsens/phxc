FROM distribution.docker-registry.svc.cluster.local/home-cluster-base:alpine

RUN apk add nginx

ENTRYPOINT ["/var/lib/home-cluster/workloads/pxe/commands/boot-server.sh"]
