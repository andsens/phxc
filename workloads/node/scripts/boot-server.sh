#!/usr/bin/env bash

exec /venv/bin/python3 -m boot-server --bind-ip "${HOST_IP:?}" --root /data
