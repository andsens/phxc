import json, logging, time, uuid
from pathlib import Path
from typing import Literal, Set, Dict
import etcd
import jwt
import jwt.algorithms
from .inmemorykvstore import InMemoryKVStore

log = logging.getLogger(__name__)

allowed_jwt_algos = filter(lambda k: k!='none', jwt.algorithms.get_default_algorithms().keys())
required_jwt_claims = ['nbf', 'exp', 'aud', 'iss', 'sub']

class NodeRegistry(object):

  client: etcd.Client | InMemoryKVStore
  admin_pubkey_path: Path

  def __init__(self, kvClient: etcd.Client | InMemoryKVStore, admin_pubkey_path: Path):
    self.client = kvClient
    self.admin_pubkey_path = admin_pubkey_path

  def __get(self, key: str):
    try:
      return self.client.read(f'/boot-server/{key}').value
    except (etcd.EtcdKeyNotFound, KeyError):
      return None

  def __set(self, key: str, val: str):
    self.client.write(f'/boot-server/{key}', val)

  def get_node_state(self, machine_id: uuid.UUID) -> Dict | None:
    return json.loads(self.__get(f'nodes/{machine_id}/state').value)

  def update_node_state(self, machine_id: uuid.UUID, node_state: Dict):
    self.__set(f'nodes/{machine_id}/state', json.dumps(node_state, indent=2))

  def get_node_config(self, machine_id: uuid.UUID) -> Dict | None:
    return json.loads(self.__get(f'nodes/{machine_id}/config').value)

  def update_node_config(self, machine_id: uuid.UUID, node_config: Dict):
    self.__set(f'nodes/{machine_id}/config', json.dumps(node_config, indent=2))

  def get_node_authn_key(self, machine_id: uuid.UUID) -> jwt.PyJWK | None:
    return jwt.PyJWK.from_json(self.__get(f'nodes/{machine_id}/authn-key').value)

  def update_node_authn_key(self, machine_id: uuid.UUID, node_authn_key: Dict):
    self.__set(f'nodes/{machine_id}/authn-key', json.dumps(node_authn_key, indent=2))

  def verify_jwt(self, token, purpose, require_admin=False) -> uuid.UUID | Literal['admin']:
    if token is None:
      raise JWTVerificationError(f'No JWT was provided')
    payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
    if 'jti' not in payload:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}, JWT must contain a JTI')
    if self.__get(f'used-jtis/{payload['jti']}') is not None:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}, the JTI {payload['jti']} has already been used')
    issuer = payload['iss']
    if require_admin:
      if issuer != 'admin':
        raise JWTVerificationError(f'Unable to verify JWT for {issuer}, issuer must be admin')
      node_authn_key = self.admin_pubkey_path.read_text()
    else:
      machine_id = uuid.UUID(issuer)
      node_authn_key = self.get_node_authn_key(machine_id)
    if node_authn_key is None:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}, no authentication key has been submitted yet')
    jwt.decode(token, key=node_authn_key, algorithms=allowed_jwt_algos, issuer=issuer, audience=['boot-server'], options={'require': required_jwt_claims})
    self.__set(f'used-jtis/{payload['jti']}', '', ttl=payload['exp'] - time.time())
    if payload['sub'] != purpose:
      raise Exception(f'Received a JWT for {issuer} with subject "{payload['sub']}", was however expecting the subject "{purpose}"')
    return issuer

  def import_host_info(self, root: Path):
    log.info('Updating state, config, and authn-key of host node')
    host_machine_id = uuid.UUID((root / 'host-machine-id').read_text())
    self.update_node_state(host_machine_id, json.loads((root / 'host-node-state.json').read_text()))
    self.update_node_config(host_machine_id, json.loads((root / 'host-node-config.json').read_text()))
    self.update_node_authn_key(host_machine_id, json.loads((root / 'host-authn-key.json').read_text()))


class NodeRegistryError(Exception):
    pass

class JWTVerificationError(NodeRegistryError):
    pass
