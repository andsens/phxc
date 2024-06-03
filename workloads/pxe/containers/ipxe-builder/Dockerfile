FROM cluster.local/home-cluster-base:debian

RUN apt-get -y update; apt-get -y install --no-install-recommends \
  ca-certificates wget gcc binutils make perl lzma-dev liblzma-dev mtools \
  ; rm -rf /var/cache/apt/lists/*

ARG IPXE_COMMIT=dc118c53696af6a0b1a8ee78fc9a4d28a217fb21
WORKDIR /ipxe
RUN wget -qO>(tar xz --strip-components 2 ipxe-${IPXE_COMMIT}/src) https://github.com/ipxe/ipxe/archive/${IPXE_COMMIT}.tar.gz
RUN sed -i 's%//\(#define NET_PROTO_IPV6\)%\1%' config/general.h
RUN make bin/ipxe.efi
