import datetime
import os
import json, shutil
import uuid
from . import Context, AuthentihashSet
from typing import List, Tuple
from pathlib import Path
from .dbobject import DBObject, get_child_keys

class Image(DBObject):

  id: uuid.UUID
  objdir = 'images'

  def __init__(self, ctx: Context, id: uuid.UUID):
    super().__init__(ctx, id)

  @property
  def variant(self):
    ret = self._get_prop('variant')
    if ret is None:
      raise Exception(f'The image {self.id} has no variant set')
    return ret

  @variant.setter
  def variant(self, variant: str):
    self._set_prop('variant', variant)

  @property
  def boot_file(self):
    ret = self._get_prop('boot-file', lambda n: self.files[n])
    if ret is None:
      raise Exception(f'The image {self.id} has no boot-file set')
    return ret

  @boot_file.setter
  def boot_file(self, boot_file: 'ImageFile'):
    self._set_prop('boot-file', boot_file.id)

  @property
  def build_date(self):
    ret = self._get_prop('build-date', datetime.datetime.fromisoformat)
    if ret is None:
      raise Exception(f'The image {self.id} has no build-date set')
    return ret

  @build_date.setter
  def build_date(self, build_date: datetime.datetime):
    self._set_prop('build-date', build_date)

  @property
  def files(self):
    return ImageFiles(self.ctx, self.key, self.abspath)

  @property
  def boot_results(self) -> 'BootResults':
    return BootResults(self.ctx, self.key)

  @property
  def abspath(self) -> Path:
    return self.ctx.images / f'{self.id}'

  def delete(self):
    super().delete()
    shutil.rmtree(self.abspath, ignore_errors=True)

  def __str__(self):
    return f'{self.variant} {self.build_date}'

  @staticmethod
  def new(ctx: Context):
    return Image(ctx, uuid.uuid4())

  @staticmethod
  def get_stable(ctx: Context, variant: str):
    """
    Returns the newest variant image that is likely to boot
    """
    available = Image.get_available(ctx, variant)
    return None if len(available) == 0 else available[0]

  @staticmethod
  def get_available(ctx: Context, variant: str):
    """
    Returns a list of variant images sorted stability first, then by age
    """
    return sorted(Image.get_all(ctx, variant), key=lambda i: len(list(i.boot_results.failed)) - len(list(i.boot_results.successful)))

  @staticmethod
  def get_all(ctx: Context, variant: str):
    """
    Returns a list of variant images sorted by age (ascending)
    """
    all_variant_images = (Image(ctx, uuid.UUID(key)) for key in get_child_keys(ctx, f'{ctx.dbprefix}/images/'))
    return sorted(all_variant_images, key=lambda i: 0 if i.build_date is None else i.build_date.timestamp(), reverse=True)


class ImageFile(DBObject):

  id: str
  abspath: Path

  def __init__(self, ctx: Context, image_key: str, abspath: Path):
    self.objdir = image_key
    super().__init__(ctx, abspath.name)
    self.abspath = abspath

  @property
  def sha256sum(self):
    return self._get_prop('sha256sum')

  @sha256sum.setter
  def sha256sum(self, sha256sum: str):
    self._set_prop('sha256sum', sha256sum)

  @property
  def authentihashset(self):
    return self._get_prop('authentihash', json.loads)

  @authentihashset.setter
  def authentihashset(self, authentihash: AuthentihashSet):
    self._set_prop('authentihash', json.dumps(authentihash, indent=2))


class ImageFiles(object):

  ctx: Context
  image_key: str
  image_abspath: Path

  def __init__(self, ctx: Context, image_key: str, image_abspath: Path):
    self.ctx = ctx
    self.image_key = image_key
    self.image_abspath = image_abspath

  def new(self, name: str | os.DirEntry | Path):
    return ImageFile(self.ctx, self.image_key, self.image_abspath / name)

  def __iter__(self):
    return map(lambda name: self.new(name), os.scandir(self.image_abspath))

  def __getitem__(self, name: str | os.DirEntry | Path):
    if name not in self:
      raise KeyError(f'{self.image_abspath} does not contain a file named "{name}"')
    return self.new(name)

  def __contains__(self, name: str | os.DirEntry | Path):
    return self.new(name).abspath.exists()


class BootResults(object):
  from .node import Node

  ctx: Context
  image_key: str

  def __init__(self, ctx: Context, image_key: str):
    self.ctx = ctx
    self.image_key = image_key

  @property
  def successful(self):
    from .node import Node
    return (Node(self.ctx, uuid.UUID(key)) for key in get_child_keys(self.ctx, f'{self.image_key}/boot-results/successful/'))

  @property
  def failed(self):
    from .node import Node
    return (Node(self.ctx, uuid.UUID(key)) for key in get_child_keys(self.ctx, f'{self.image_key}/boot-results/failed/'))

  def log_success(self, node: Node):
    self.ctx.db.delete(f'{self.image_key}/boot-results/failed/{node.id}')
    self.ctx.db.set(f'{self.image_key}/boot-results/successful/{node.id}', '')

  def log_failure(self, node: Node):
    self.ctx.db.delete(f'{self.image_key}/boot-results/successful/{node.id}')
    self.ctx.db.set(f'{self.image_key}/boot-results/failed/{node.id}', '')
