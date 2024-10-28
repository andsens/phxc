import etcd
from .inmemorykvstore import InMemoryKVStore

class DB(object):

  client: etcd.Client | InMemoryKVStore
  prefix: str

  def __init__(self, client: etcd.Client | InMemoryKVStore, prefix: str):
    self.client = client
    self.prefix = prefix

  def get(self, key: str):
    try:
      return self.client.read(f'{self.prefix}{key}').value
    except (etcd.EtcdKeyNotFound, KeyError):
      return None

  def set(self, key: str, val: str, ttl: int | None = None):
    self.client.write(f'{self.prefix}{key}', val, ttl=ttl)

  def read(self, key: str, recursive=False):
    self.client.read(key, recursive)
