import time, uuid
from pathlib import Path
from typing import Literal
import etcd
import jwt
import jwt.algorithms
from . import JWTVerificationError
from .inmemorykvstore import InMemoryKVStore
from .node import Node

allowed_jwt_algos = [k for k in jwt.algorithms.get_default_algorithms().keys() if k != 'none']
required_jwt_claims = ['nbf', 'exp', 'aud', 'iss', 'sub']

class JWTChecker(object):

  client: etcd.Client | InMemoryKVStore
  admin_pubkey_path: Path

  def __init__(self, kv_client: etcd.Client | InMemoryKVStore, admin_pubkey_path: Path):
    self.client = kv_client
    self.admin_pubkey_path = admin_pubkey_path

  def verify_jwt(self, token: str, jwk: str | jwt.PyJWK, subject: str):
    payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
    issuer = payload['iss']
    if 'jti' not in payload:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JWT must contain a JTI')
    if self.__get(f'used-jtis/{payload['jti']}') is not None:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JTI {payload['jti']} has already been used')
    jwt.decode(token, key=jwk, algorithms=allowed_jwt_algos,
               issuer=issuer, audience=['boot-server'],
               options={'require': required_jwt_claims}, leeway=30)
    self.__set(f'used-jtis/{payload['jti']}', '', ttl=int(payload['exp'] - time.time()) + 1)
    if payload['sub'] != subject:
      raise JWTVerificationError(f'Received a JWT for {issuer} with subject "{payload['sub']}", was however expecting the subject "{subject}"')

  def verify_admin_jwt(self, token, subject):
    issuer = get_jwt_issuer(token)
    if issuer != 'admin':
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be admin')
    jwk = self.admin_pubkey_path.read_text()
    self.verify_jwt(token, jwk, subject)


  def verify_node_jwt(self, token, subject) -> Node:
    issuer = get_jwt_issuer(token)
    try:
      node = Node(self.client, uuid.UUID(issuer))
    except ValueError:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be a machine-id')
    jwk = node.get_authn_key()
    if jwk is None:
      raise JWTVerificationError(f'Unable to verify JWT for {issuer}: No authentication key has been submitted yet')
    self.verify_jwt(token, jwk, subject)
    return node


def get_jwt_issuer(token) -> Node | Literal['admin']:
  if token is None:
    raise JWTVerificationError(f'No JWT was provided')
  payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
  issuer = payload['iss']
  return issuer
