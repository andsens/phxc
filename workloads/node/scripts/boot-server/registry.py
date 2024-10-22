import json, logging, time, uuid
from pathlib import Path
from typing import Literal, Dict
import etcd, macaddress
from . import AnyIPAddress, NodeState, NodeConfig
import jwt
import jwt.algorithms
from . import JWTVerificationError
from .inmemorykvstore import InMemoryKVStore
from typing import overload

log = logging.getLogger(__name__)

allowed_jwt_algos = [k for k in jwt.algorithms.get_default_algorithms().keys() if k != 'none']
required_jwt_claims = ['nbf', 'exp', 'aud', 'iss', 'sub']

class Registry(object):

  client: etcd.Client | InMemoryKVStore
  ip_to_mac_ttl = 3600
  admin_pubkey_path: Path

  def __init__(self, kvClient: etcd.Client | InMemoryKVStore, admin_pubkey_path: Path):
    self.client = kvClient
    self.admin_pubkey_path = admin_pubkey_path

  def __get(self, key: str):
    try:
      return self.client.read(f'/boot-server/{key}').value
    except (etcd.EtcdKeyNotFound, KeyError):
      return None

  def __set(self, key: str, val: str, ttl: int | None = None):
    self.client.write(f'/boot-server/{key}', val, ttl=ttl)

  def ip_requested(self, mac: macaddress.MAC, ip: AnyIPAddress):
    self.__set(f'ip-to-mac/{ip}', mac, self.ip_to_mac_ttl)
    self.__set(f'mac-to-ip/{mac}', ip, self.ip_to_mac_ttl)

  def get_machine_id_by_mac(self, mac: macaddress.MAC) -> uuid.UUID | None:
    machine_id = self.__get(f'mac-to-machine-id/{mac}')
    return uuid.UUID(machine_id) if machine_id is not None else None

  def get_machine_id_by_ip(self, ip: AnyIPAddress) -> uuid.UUID | None:
    mac = self.__get(f'ip-to-mac/{ip}')
    return self.get_machine_id_by_mac(mac) if mac is not None else None

  def get_all_machine_ids(self) -> list[uuid.UUID]:
    prefix = '/boot-server/nodes/states/'
    try:
      return map(lambda n: uuid.UUID(n.key[len(prefix):]), self.client.read(prefix, recursive=True).children)
    except (etcd.EtcdKeyNotFound, KeyError):
      return []

  def get_node_authn_key(self, machine_id: uuid.UUID) -> jwt.PyJWK | None:
    authn_key = self.__get(f'nodes/authn-keys/{machine_id}')
    return jwt.PyJWK.from_json(authn_key) if authn_key is not None else None

  def update_node_authn_key(self, machine_id: uuid.UUID, node_authn_key: Dict):
    self.__set(f'nodes/authn-keys/{machine_id}', json.dumps(node_authn_key, indent=2))

  def get_node_config(self, machine_id: uuid.UUID) -> NodeConfig | None:
    config = self.__get(f'nodes/configs/{machine_id}')
    return json.loads(config) if config is not None else None

  def update_node_config(self, machine_id: uuid.UUID, node_config: NodeConfig):
    self.__set(f'nodes/configs/{machine_id}', json.dumps(node_config, indent=2))

  def get_node_state(self, machine_id: uuid.UUID) -> NodeState | None:
    state = self.__get(f'nodes/states/{machine_id}')
    return json.loads(state) if state is not None else None

  def update_node_state(self, machine_id: uuid.UUID, node_state: NodeState):
    self.__set(f'nodes/states/{machine_id}', json.dumps(node_state, indent=2))
    self.__set(f'mac-to-machine-id/{node_state['primary-mac']}', machine_id)

  def verify_jwt(self, token, subject, require_admin=False) -> uuid.UUID | Literal['admin']:
    if token is None:
      raise JWTVerificationError(f'No JWT was provided')
    payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
    issuer = payload['iss']
    if 'jti' not in payload:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JWT must contain a JTI')
    if self.__get(f'used-jtis/{payload['jti']}') is not None:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JTI {payload['jti']} has already been used')
    if require_admin:
      if issuer != 'admin':
        raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be admin')
      issuer_return = issuer
      node_authn_key = self.admin_pubkey_path.read_text()
    else:
      machine_id = uuid.UUID(issuer)
      issuer_return = machine_id
      node_authn_key = self.get_node_authn_key(machine_id)
    if node_authn_key is None:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: No authentication key has been submitted yet')
    jwt.decode(token, key=node_authn_key, algorithms=allowed_jwt_algos,
               issuer=issuer, audience=['boot-server'],
               options={'require': required_jwt_claims}, leeway=30)
    self.__set(f'used-jtis/{payload['jti']}', '', ttl=int(payload['exp'] - time.time()) + 1)
    if payload['sub'] != subject:
      raise Exception(f'Received a JWT for {issuer} with subject "{payload['sub']}", was however expecting the subject "{subject}"')
    return issuer_return

  def import_host_info(self, import_path: Path):
    log.info('Updating state, config, and authn-key of host node')
    host_machine_id = uuid.UUID((import_path / 'machine-id').read_text())
    self.update_node_state(host_machine_id, json.loads((import_path / 'node-state.json').read_text()))
    self.update_node_config(host_machine_id, json.loads((import_path / 'node-config.json').read_text()))
    self.update_node_authn_key(host_machine_id, json.loads((import_path / 'authn-key.json').read_text()))

  @overload
  def get_variant_dir(self, ipaddr: AnyIPAddress, variant) -> Path:
    machine_id = self.get_machine_id_by_ip(ipaddr)
    if machine_id is None:
      log.warning(f'Failed to map IP address {ipaddr} to a known machine-id')
      return Path(variant)
    else:
      return self.get_variant_dir(machine_id)

  @overload
  def get_variant_dir(self, mac: macaddress.MAC, variant) -> Path:
    machine_id = self.get_machine_id_by_mac(mac)
    if machine_id is None:
      log.warning(f'Failed to map MAC address {mac} to a known machine-id')
      return Path(variant)
    else:
      return self.get_variant_dir(machine_id)

  def get_variant_dir(self, machine_id: uuid.UUID, variant) -> Path:
    return Path(variant)
