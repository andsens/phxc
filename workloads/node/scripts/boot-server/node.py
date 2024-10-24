import json, uuid
import uuid
import etcd
import jwt
from .inmemorykvstore import InMemoryKVStore
from . import NodeState, NodeConfig
from typing import Dict

class Node(object):

  client: etcd.Client | InMemoryKVStore
  machine_id: uuid.UUID

  def __init__(self, kv_client: etcd.Client | InMemoryKVStore, machine_id: uuid.UUID):
    self.client = kv_client
    self.machine_id = machine_id

  def __get(self, key: str):
    try:
      return self.client.read(f'/boot-server/{key}').value
    except (etcd.EtcdKeyNotFound, KeyError):
      return None

  def __set(self, key: str, val: str, ttl: int | None = None):
    self.client.write(f'/boot-server/{key}', val, ttl=ttl)

  def get_authn_key(self) -> jwt.PyJWK | None:
    authn_key = self.__get(f'nodes/authn-keys/{self.machine_id}')
    return jwt.PyJWK.from_json(authn_key) if authn_key is not None else None

  def set_authn_key(self, authn_key: Dict):
    self.__set(f'nodes/authn-keys/{self.machine_id}', json.dumps(authn_key, indent=2))

  def get_config(self) -> NodeConfig | None:
    config = self.__get(f'nodes/configs/{self.machine_id}')
    return json.loads(config) if config is not None else None

  def set_config(self, config: NodeConfig):
    self.__set(f'nodes/configs/{self.machine_id}', json.dumps(config, indent=2))

  def get_state(self) -> NodeState | None:
    state = self.__get(f'nodes/states/{self.machine_id}')
    return json.loads(state) if state is not None else None

  def set_state(self, state: NodeState):
    self.__set(f'nodes/states/{self.machine_id}', json.dumps(state, indent=2))
    self.__set(f'mac-to-machine-id/{state['primary-mac']}', self.machine_id)
