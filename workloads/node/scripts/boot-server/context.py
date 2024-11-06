import asyncio
from pathlib import Path
from typing import TypedDict, Pattern
from .db import DB
from . import AnyIPAddress


class BootPath(TypedDict):
  variant: str
  filename: str

class Config(TypedDict):
  host_ip: AnyIPAddress
  ip_to_mac_ttl: int
  images: Path
  tls_certfile: Path
  tls_keyfile: Path
  admin_pubkey: str
  sb_pubkey: str
  steppath: Path | None

class Context(TypedDict):
  db: DB
  config: Config
  boot_map: dict[Pattern, BootPath]
  shutdown_event: asyncio.Event
