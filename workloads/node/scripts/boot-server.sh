#!/usr/bin/env bash

exec /venv/bin/python3 -m boot-server \
  --listen "${HOST_IP:?}" \
  --import /data/host \
  --etcd "${ETCD_URL:?}"
