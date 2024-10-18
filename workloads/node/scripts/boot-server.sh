#!/usr/bin/env bash

exec /venv/bin/python3 -m boot-server \
  --listen "${HOST_IP:?}" \
  --root /data \
  --import \
  --etcd "${ETCD_URL:?}"
