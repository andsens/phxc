import time


class InMemoryKVStore(object):

  store: dict[str, tuple[str, int]]

  def __init__(self):
    self.store = {}

  def write(self, key: str, value: str, ttl: int | None = None):
    self.store[key] = (value, None if ttl is None else time.time() + ttl)

  def read(self, key: str):
    if key in self.store:
      (value, expiry) = self.store[key]
      if expiry is not None and expiry > time.time():
        del self.store[key]
        return None
      else:
        return value
    else:
      return None
