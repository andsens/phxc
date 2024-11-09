#!/usr/bin/env bash

exec /venv/bin/python3 -m boot-server "${HOST_IP:?}" "${ETCD_URL:?}"
