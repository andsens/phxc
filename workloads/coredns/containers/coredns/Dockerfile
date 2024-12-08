# Source: https://github.com/ori-edge/k8s_gateway/blob/v0.4.0/Dockerfile
FROM --platform=$BUILDPLATFORM golang:1.23.4-bookworm AS build
SHELL [ "/bin/bash", "-ec" ]

WORKDIR /src
RUN apt-get update; apt-get install -y ca-certificates wget libcap2-bin
RUN wget -qO- https://github.com/coredns/coredns/archive/refs/tags/v1.12.0.tar.gz | tar xz --strip-components=1
RUN go get github.com/ori-edge/k8s_gateway@v0.4.0
RUN echo k8s_gateway:github.com/ori-edge/k8s_gateway >>plugin.cfg
RUN make coredns BINARY=coredns SYSTEM="GOOS=linux GOARCH=${BUILDPLATFORM}"
RUN setcap cap_net_bind_service=+ep /src/coredns

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build --chmod=0755 /src/coredns /coredns
USER nonroot:nonroot
WORKDIR /
EXPOSE 53 53/udp
ENTRYPOINT ["/coredns"]
