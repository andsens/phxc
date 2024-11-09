import ipaddress
import json, uuid, logging
import uuid
import jwt
from . import AnyIPAddress, EtcdResult, NodeState, NodeConfig, Context
import macaddress
from typing import cast
from .dbobject import DBObject, get_child_keys
from .image import Image

log = logging.getLogger(__name__)

class Node(DBObject):

  id: uuid.UUID
  objdir = 'nodes'

  def __init__(self, ctx: Context, id: uuid.UUID):
    super().__init__(ctx, id)

  @property
  def variant(self):
    ret = self._get_prop('variant')
    if ret is None:
      raise Exception(f'The node {self.id} has no variant set')
    return ret

  @variant.setter
  def variant(self, variant: str):
    self._set_prop('variant', variant)

  @property
  def mac_address(self):
    return self._get_prop('mac-address', macaddress.MAC)

  @mac_address.setter
  def mac_address(self, mac_address: macaddress.MAC):
    self._set_prop('mac-address', str(mac_address))
    self.ctx.db.set(f'{self.ctx.dbprefix}/node-ids-by-mac/{mac_address}', self.id)

  @property
  def ip(self):
    return self._get_prop('ip', ipaddress.ip_address)

  @ip.setter
  def ip(self, ip: AnyIPAddress):
    self._set_prop('ip', ip, self.ctx.ip_to_mac_ttl)
    self.ctx.db.set(f'{self.ctx.dbprefix}/node-ids-by-ip/{ip}', self.id, self.ctx.ip_to_mac_ttl)

  @property
  def machine_id(self):
    return self._get_prop('machine-id', uuid.UUID)

  @machine_id.setter
  def machine_id(self, machine_id: uuid.UUID):
    self._set_prop('machine-id', machine_id)
    self.ctx.db.set(f'{self.ctx.dbprefix}/node-ids-by-machine-id/{machine_id}', self.id)

  @property
  def hostname(self):
    return self._get_prop('hostname')

  @hostname.setter
  def hostname(self, hostname: str):
    self._set_prop('hostname', hostname)

  @property
  def authn_key(self):
    return self._get_prop('authn-key', jwt.PyJWK.from_json)

  @authn_key.setter
  def authn_key(self, authn_key: jwt.PyJWK):
    self._set_prop('authn-key', json.dumps(authn_key, indent=2))

  @property
  def bootnext_image(self):
    return self._get_prop('bootnext-image', lambda id: Image(self.ctx, uuid.UUID(id)))

  @bootnext_image.setter
  def bootnext_image(self, bootnext_image: Image):
    self._set_prop('bootnext-image', bootnext_image.id)

  @bootnext_image.deleter
  def bootnext_image(self):
    self._del_prop('bootnext-image')

  @property
  def booting_image(self):
    ret = self._get_prop('booting-image', lambda id: Image(self.ctx, uuid.UUID(id)))
    return ret

  @booting_image.setter
  def booting_image(self, image: Image):
    self._set_prop('booting-image', image.id)

  @booting_image.deleter
  def booting_image(self):
    self._del_prop('booting-image')

  @property
  def stable_image(self):
    return self._get_prop('stable-image', lambda id: Image(self.ctx, uuid.UUID(id)))

  @stable_image.setter
  def stable_image(self, stable_image: Image):
    self._set_prop('stable-image', stable_image.id)

  def delete(self):
    if self.mac_address is not None:
      self.ctx.db.delete(f'{self.ctx.dbprefix}/node-ids-by-mac/{self.mac_address}')
    if self.machine_id is not None:
      self.ctx.db.delete(f'{self.ctx.dbprefix}/node-ids-by-machine-id/{self.machine_id}')
    super().delete()

  def __str__(self) -> str:
    return str(self.hostname or self.machine_id or self.key)

  def get_config(self) -> NodeConfig | None:
    return self._get_prop('config', json.loads)

  def set_config(self, config: NodeConfig):
    self._set_prop('config', json.dumps(config, indent=2))

  def get_state(self) -> NodeState | None:
    return self._get_prop('state', json.loads)

  def set_state(self, state: NodeState):
    self._set_prop('state', json.dumps(state, indent=2))

  @staticmethod
  def new_by_mac(ctx: Context, mac: macaddress.MAC):
    node_id = uuid.uuid4()
    ctx.db.set(f'{ctx.dbprefix}/node-ids-by-mac/{mac}', node_id)
    return Node(ctx, node_id)

  @staticmethod
  def get_by_mac(ctx: Context, mac: macaddress.MAC):
    node_id = cast(EtcdResult, ctx.db.get(f'{ctx.dbprefix}/node-ids-by-mac/{mac}')).value
    if node_id is None:
      return None
    return Node(ctx, uuid.UUID(node_id))

  @staticmethod
  def get_by_ip(ctx: Context, ip: AnyIPAddress):
    node_id = cast(EtcdResult, ctx.db.get(f'{ctx.dbprefix}/node-ids-by-ip/{ip}')).value
    if node_id is None:
      return None
    return Node(ctx, uuid.UUID(node_id))

  @staticmethod
  def get_by_machine_id(ctx: Context, machine_id: uuid.UUID):
    node_id = cast(EtcdResult, ctx.db.get(f'{ctx.dbprefix}/node-ids-by-machine-id/{machine_id}')).value
    if node_id is None:
      return None
    return Node(ctx, uuid.UUID(node_id))

  @staticmethod
  def get_all(ctx: Context):
    return (Image(ctx, uuid.UUID(key)) for key in get_child_keys(ctx, f'{ctx.dbprefix}/nodes/'))
