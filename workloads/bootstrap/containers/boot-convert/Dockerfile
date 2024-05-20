ARG IMAGE
FROM $IMAGE

RUN setup-boot-convert
ENTRYPOINT ["/var/lib/home-cluster/workloads/bootstrap/containers/boot-convert/create-bootable-image.sh"]
