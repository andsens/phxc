import asyncio
import etcd
from typing import TypedDict
from .registry import Registry
from .inmemorykvstore import InMemoryKVStore
from .jwt_checker import JWTChecker

class Context(TypedDict):
  registry: Registry
  jwt_checker: JWTChecker
  kvClient: etcd.Client | InMemoryKVStore
  shutdown_event: asyncio.Event
