import etcd
from . import Context, EtcdResult
from typing import Any, Callable, Generator, cast, overload


class DBObject(object):

  ctx: Context
  id: Any
  objdir: str
  key: str

  def __init__(self, ctx: Context, id: Any):
    self.ctx = ctx
    self.id = id
    self.key = f'{ctx.dbprefix}/{self.objdir}/{id}'

  @overload
  def _get_prop[T](self, prop: str, constructor: Callable[[str], T]) -> T | None: ...

  @overload
  def _get_prop(self, prop: str, constructor: None = None) -> str | None: ...

  def _get_prop[T](self, prop: str, constructor: Callable[[str], T] | None = None) -> T | str | None:
    return load_or_none(self.ctx, f'{self.key}/{prop}', constructor)

  def _set_prop(self, prop: str, val: Any, ttl: int | None = None):
    self.ctx.db.set(f'{self.key}/{prop}', str(val), ttl)

  def _del_prop(self, prop: str):
    self.ctx.db.delete(f'{self.key}/{prop}')

  def delete(self):
    self.ctx.db.delete(f'{self.key}', recursive=True)

@overload
def load_or_none[T](ctx: Context, key: str, constructor: Callable[[str], T]) -> T | None: ...
@overload
def load_or_none(ctx: Context, key: str, constructor: None = None) -> str | None: ...

def load_or_none[T](ctx: Context, key: str, constructor: Callable[[str], T] | None = None) -> T | str | None:
  try:
    val = cast(EtcdResult, ctx.db.get(f'{key}')).value
    return val if constructor is None else constructor(val)
  except (etcd.EtcdKeyNotFound):
    return None

def get_child_keys(ctx: Context, key: str) -> Generator[str, None, None]:
  return (res.key[len(key):] for res in ctx.db.read(key, recursive=True).get_subtree() if '/' not in res.key[len(key):]) # type: ignore
