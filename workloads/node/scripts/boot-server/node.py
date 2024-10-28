import json, uuid
import uuid
import etcd
import jwt
from . import AnyIPAddress, NodeState, NodeConfig
import macaddress
from typing import Dict, Self
from .context import Context

class Node(object):

  context: Context
  machine_id: uuid.UUID

  def __init__(self, context: Context, machine_id: uuid.UUID):
    self.context = context
    self.machine_id = machine_id

  def get_authn_key(self) -> jwt.PyJWK | None:
    authn_key = self.context['db'].get(f'nodes/authn-keys/{self.machine_id}')
    return jwt.PyJWK.from_json(authn_key) if authn_key is not None else None

  def set_authn_key(self, authn_key: Dict):
    self.context['db'].set(f'nodes/authn-keys/{self.machine_id}', json.dumps(authn_key, indent=2))

  def get_config(self) -> NodeConfig | None:
    config = self.context['db'].get(f'nodes/configs/{self.machine_id}')
    return json.loads(config) if config is not None else None

  def set_config(self, config: NodeConfig):
    self.context['db'].set(f'nodes/configs/{self.machine_id}', json.dumps(config, indent=2))

  def get_state(self) -> NodeState | None:
    state = self.context['db'].get(f'nodes/states/{self.machine_id}')
    return json.loads(state) if state is not None else None

  def set_state(self, state: NodeState):
    self.context['db'].set(f'nodes/states/{self.machine_id}', json.dumps(state, indent=2))
    self.context['db'].set(f'mac-to-machine-id/{state['primary-mac']}', self.machine_id)

  @staticmethod
  def ip_requested(context: Context, mac: macaddress.MAC, ip: AnyIPAddress):
    context['db'].set(f'ip-to-mac/{ip}', mac, context['config']['ip_to_mac_ttl'])
    context['db'].set(f'mac-to-ip/{mac}', ip, context['config']['ip_to_mac_ttl'])

  @staticmethod
  def get_by_mac(context: Context, mac: macaddress.MAC) -> Self | None:
    machine_id = context['db'].get(f'mac-to-machine-id/{mac}')
    return Node(context, uuid.UUID(machine_id)) if machine_id is not None else None

  @staticmethod
  def get_by_ip(context: Context, ip: AnyIPAddress) -> Self | None:
    mac = context['db'].get(f'ip-to-mac/{ip}')
    return Node.get_by_mac(context, mac) if mac is not None else None

  @staticmethod
  def get_all(context: Context) -> list[Self]:
    prefix = '/boot-server/nodes/states/'
    try:
      return map(lambda n: Node(context, uuid.UUID(n.key[len(prefix):])), context['db'].read(prefix, recursive=True).children)
    except (etcd.EtcdKeyNotFound, KeyError):
      return []
