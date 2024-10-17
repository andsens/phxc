#!/usr/bin/python3

import collections, json, logging, subprocess, sys, time, uuid
from pathlib import Path
from typing import Literal, Set, Dict

log = logging.getLogger(__name__)

UsedJTI = collections.namedtuple('UsedJTI', ['expires', 'id'])

class NodeRegistry(object):

  root: Path
  admin_pubkey_path: Path
  used_jtis: Set[str]

  def __init__(self, root: Path, admin_pubkey_path: Path):
    self.root = root
    self.admin_pubkey_path = admin_pubkey_path
    self.used_jtis = set()

  def get_node_state(self, machine_id: uuid.UUID) -> Dict | None:
    node_state_path: Path = self.root / 'node-states' / f'{machine_id}.json'
    try:
      with node_state_path.open('r') as h:
        return json.loads(h.read())
    except Exception as e:
      log.exception(e)
      return None

  def update_node_state(self, machine_id: uuid.UUID, node_state: Dict):
    node_state_path: Path = self.root / 'node-states' / f'{machine_id}.json'
    with node_state_path.open('w') as h:
      h.write(json.dumps(node_state, indent=2))

  def get_node_config(self, machine_id: uuid.UUID) -> Dict | None:
    node_config_path: Path = self.root / 'node-configs' / f'{machine_id}.json'
    try:
      with node_config_path.open('r') as h:
        return json.loads(h.read())
    except Exception as e:
      log.exception(e)
      return None

  def update_node_config(self, machine_id: uuid.UUID, node_config: Dict):
    node_config_path: Path = self.root / 'node-configs' / f'{machine_id}.json'
    with node_config_path.open('w') as h:
      h.write(json.dumps(node_config, indent=2))

  def get_node_authn_key(self, machine_id: uuid.UUID) -> Dict | None:
    node_authn_key_path: Path = self.root / 'node-authn-key' / f'{machine_id}.json'
    try:
      with node_authn_key_path.open('r') as h:
        return json.loads(h.read())
    except Exception as e:
      log.exception(e)
      return None

  def update_node_authn_key(self, machine_id: uuid.UUID, node_authn_key: Dict):
    node_authn_key_path: Path = self.root / 'node-authn-keys' / f'{machine_id}.json'
    with node_authn_key_path.open('w') as h:
      h.write(json.dumps(node_authn_key, indent=2))

  def verify_jwt(self, jwt, purpose, require_admin=False) -> uuid.UUID | Literal['admin']:
    if jwt is None:
      raise JWTVerificationError(f'No JWT was provided')
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    if 'jti' not in jwt_data['payload']:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}, JWT must contain a JTI')
    jti = jwt_data['payload']['jti']
    if any(map(lambda used_jti: used_jti.id == jti, self.used_jtis)):
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}, the JTI {jti} has already been used')
    issuer = jwt_data['payload']['iss']
    if require_admin:
      if issuer != 'admin':
        raise JWTVerificationError(f'Unable to verify JWT for {issuer}, issuer must be admin')
      node_authn_key_path: Path = self.admin_pubkey_path
    else:
      issuer = uuid.UUID(issuer)
      node_authn_key_path: Path = self.root / 'node-authn-keys' / f'{issuer}.json'
    if not node_authn_key_path.exists():
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}, no authentication key has been submitted yet')
    subprocess.check_output(
      ['step', 'crypto', 'jwt', 'verify', '--iss', issuer, '--aud', 'boot-server', '--key', node_authn_key_path],
      input=jwt.encode(),
      stderr=sys.stderr
    )
    self.used_jtis.add(UsedJTI(jwt_data['payload']['exp'], jwt_data['payload']['jti']))
    if jwt_data['payload']['sub'] != purpose:
      raise Exception(f'Received a JWT for {issuer} with subject "{jwt_data['payload']['sub']}", was however expecting the subject "{purpose}"')
    self.used_jtis = set(filter(lambda used_jti: used_jti.expires < time.time(), self.used_jtis))
    return issuer


class NodeRegistryError(Exception):
    pass

class JWTVerificationError(NodeRegistryError):
    pass
