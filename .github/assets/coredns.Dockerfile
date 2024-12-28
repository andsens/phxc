# Source: https://github.com/ori-edge/k8s_gateway/blob/v0.4.0/Dockerfile
ARG GO_VERSION
FROM golang:${GO_VERSION}-bookworm AS build
SHELL [ "/bin/bash", "-ec" ]

ARG TARGETARCH
ARG COREDNS_VERSION
ARG K8SGW_VERSION

WORKDIR /src
RUN <<EOR
apt-get update; apt-get install -y ca-certificates wget libcap2-bin
wget -qO- https://github.com/coredns/coredns/archive/refs/tags/v${COREDNS_VERSION}.tar.gz | tar xz --strip-components=1
go get github.com/ori-edge/k8s_gateway@v${K8SGW_VERSION}
echo k8s_gateway:github.com/ori-edge/k8s_gateway >>plugin.cfg
make coredns BINARY=coredns SYSTEM="GOOS=linux GOARCH=${TARGETARCH}"
setcap cap_net_bind_service=+ep /src/coredns
EOR

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build --chmod=0755 /src/coredns /coredns
USER nonroot:nonroot
WORKDIR /
EXPOSE 53 53/udp
ENTRYPOINT ["/coredns"]
