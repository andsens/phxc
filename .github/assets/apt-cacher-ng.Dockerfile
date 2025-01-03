FROM debian:trixie
SHELL ["/usr/bin/bash", "-Eeo", "pipefail", "-c"]

RUN <<EOR
apt-get -y update
apt-get -y install --no-install-recommends apt-cacher-ng
rm -rf /var/cache/apt/lists/*

ln -sf /dev/stdout /var/log/apt-cacher-ng/apt-cacher.log
ln -sf /dev/stderr /var/log/apt-cacher-ng/apt-cacher.err
EOR

ENTRYPOINT ["/usr/sbin/apt-cacher-ng", "-c", "/etc/apt-cacher-ng"]
