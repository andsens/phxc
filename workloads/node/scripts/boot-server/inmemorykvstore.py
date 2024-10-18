import time


class InMemoryKVStore(object):

  store: dict[str, tuple[str, int]]

  def __init__(self):
    self.store = {}

  def write(self, key: str, value: str, ttl: int | None = None):
    self.store[key] = (value, None if ttl is None else int(time.time()) + ttl)

  def read(self, key: str, recursive=False):
    now = int(time.time())
    if recursive:
      children = []
      for subkey, (value, expires) in self.store.items():
        ttl = expires - now if expires is not None else None
        if ttl is not None and ttl <= 0:
          del self.store[key]
          continue
        if subkey.startswith(key):
          children.append(KVStoreResult(subkey, value, ttl))
      return KVStoreResult(key, children)
    elif key in self.store:
      (value, expires) = self.store[key]
      ttl = expires - now if expires is not None else None
      if ttl is not None and ttl <= 0:
        del self.store[key]
        raise KeyError(f'key {key} not found in InMemoryKVStore')
      else:
        return KVStoreResult(key, value, ttl)
    else:
      raise KeyError(f'key {key} not found in InMemoryKVStore')


class KVStoreResult(object):

  key: str
  ttl: int | None

  def __init__(self, key: str, value, ttl: int | None):
    self.key = key
    if type(value) is list:
      self.children = value
    else:
      self.value = value
    self.ttl = ttl
