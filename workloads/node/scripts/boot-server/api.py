#!/usr/bin/python3

import asyncio
import os, logging, tempfile, shutil, tarfile, tempfile, uuid
from pathlib import Path
import quart
from hypercorn.config import Config
from hypercorn.asyncio import serve
from werkzeug.exceptions import HTTPException, NotFound, BadRequest, Forbidden, InternalServerError, ServiceUnavailable
import jwt
from .context import Context
from .node import Node
import time, uuid
from typing import Literal
import jwt
import jwt.algorithms
from .node import Node
from .context import Context

DISK_UUID='caf66bff-edab-4fb1-8ad9-e570be5415d7'

log = logging.getLogger(__name__)

app = quart.Quart(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

async def api(ready_event: asyncio.Event, context: Context):
  log.info('Starting registry API')
  global app
  app.config['context'] = context
  config = Config()
  config.keyfile = context['config']['tls_keyfile']
  config.certfile = context['config']['tls_certfile']
  config.bind = [f'{context['config']['host_ip']}:8020']
  config.accesslog = '-'
  ready_event.set()
  await serve(app, config, shutdown_trigger=context['shutdown_event'].wait)
  log.info('Closed registry API')

transfers_completed = {
  'root_key': False,
  'secureboot_cert': False,
  'secureboot_key': False,
}

@app.errorhandler(HTTPException)
def handle_http_exception(e: HTTPException):
  log.error(e.description)
  return e.description, e.code

@app.errorhandler(Exception)
def handle_other_exceptions(e: Exception):
  log.exception(e)
  return 'Internal server error', 500

@app.get('/')
async def get_root():
  raise

@app.get('/images/<path:image_path>')
async def get_image(image_path):
  if not (app.config['context']['config']['images'] / image_path).exists():
    raise NotFound(f'The image {image_path} could not be found')
  log.info(f'Sending {image_path}')
  return await quart.send_file(app.config['context']['config']['images'] / image_path)

@app.put('/images/<path:variant>')
async def put_image(variant):
  verify_bootstrap_jwt()
  if 'image' not in await quart.request.files:
    raise BadRequest('No image was included in the upload request')
  image_path: Path = app.config['context']['config']['images'] / f'{variant}.uploading'
  image_path_uploaded: Path = app.config['context']['config']['images'] / f'{variant}.uploaded'
  log.info(f'Saving image to {image_path}')
  shutil.rmtree(image_path, ignore_errors=True)
  image_path.mkdir()
  try:
    tmp = tempfile.NamedTemporaryFile(delete_on_close=False)
    try:
      tmp.close()
      await (await quart.request.files)['image'].save(tmp.name)
      with tarfile.TarFile(tmp.name) as image_archive:
        image_archive.extractall(path=image_path)
    except Exception as e:
      tmp.delete()
      raise InternalServerError(str(e))
    shutil.rmtree(image_path_uploaded, ignore_errors=True)
    image_path.rename(image_path_uploaded)
  except Exception as e:
    shutil.rmtree(image_path, ignore_errors=True)
    raise InternalServerError(str(e))
  return {'result': 'OK'}

@app.get('/health')
async def get_health():
  return ''

@app.put('/authn-key')
async def put_node_authn_key():
  token = get_jwt_auth_header()

  payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
  node = Node(app.config['context'], uuid.UUID(payload['iss']))
  submitted_node_authn_key = await quart.request.get_json()
  if submitted_node_authn_key is None:
    raise BadRequest('No authn-key was supplied in the request body')

  node_state = node.get_state()
  node_authn_key_persisted = False
  if node_state is not None:
    node_authn_key_persisted = node_state.get('keys', {}).get('authn', {}).get('persisted', False)

  existing_node_authn_key = node.get_authn_key()
  if node_authn_key_persisted and existing_node_authn_key is not None:
    # When a key for an existing node is submitted, validate the JWT using the store key
    verify_node_jwt()
  else:
    # When a key for a new node is submitted, validate the JWT using the submitted key
    jwt.decode(token, key=jwt.PyJWK.from_dict(submitted_node_authn_key),
                algorithms=allowed_jwt_algos, issuer=payload['iss'], audience=['boot-server'],
                options={'require': required_jwt_claims}, leeway=30)
  log.info(f'Saving authn key for {node.machine_id}')
  node.set_authn_key(submitted_node_authn_key)
  return {'result': 'OK'}

@app.get('/machine-ids')
async def get_machine_ids():
  verify_admin_jwt()
  machine_ids = Node.get_all(app.config['context'])
  return list(machine_ids)

@app.get('/config')
async def get_node_config():
  node = verify_node_jwt()
  node_config = node.get_config()
  if node_config is None:
    raise NotFound(f'The node {node.machine_id} is not configured, run `bin/configure-node {node.machine_id}` to do that')
  log.info(f'Sending node-config to {node.machine_id}')
  return node_config

@app.get('/config/<machine_id>')
async def get_node_config_by_machine_id(machine_id):
  verify_admin_jwt()
  node_config = Node(app.config['context'], uuid.UUID(machine_id))
  if node_config is None:
    raise NotFound(f'Unable to find a node-config for the node {machine_id}')
  return node_config

@app.put('/config/<machine_id>')
async def update_node_config(machine_id):
  verify_admin_jwt()
  new_node_config = await quart.request.get_json()
  if new_node_config is None:
    raise BadRequest('No node-config was supplied in the request body')
  Node(app.config['context'], uuid.UUID(machine_id)).set_config(new_node_config)
  return {'result': 'OK'}

@app.put('/state')
async def put_node_state():
  node = verify_node_jwt()
  log.info(f'Saving node-state for {node.machine_id}')
  new_node_state = await quart.request.get_json()
  node.set_state(new_node_state)
  node_config = node.get_config()
  if node_config is not None:
    if node_config['disk'].get('force', False) == True:
      selected_block_device = next(
        filter(lambda bd: bd['devpath'] == node_config['disk']['devpath'], new_node_state['blockdevices']),
        None
      )
      if selected_block_device.get('partitions', {}).get('partitiontable', {}).get('id', None).lower() == DISK_UUID:
        del node_config['disk']['force']
        node.set_config(node_config)
  return {'result': 'OK'}

@app.get('/state/<machine_id>')
async def get_node_state_by_machine_id(machine_id):
  verify_admin_jwt()
  node_state = Node(app.config['context'], uuid.UUID(machine_id))
  if node_state is None:
    raise NotFound(f'Unable to find a node-state for the node {machine_id}')
  return node_state

@app.get('/transfer-enabled')
async def transfer_enabled():
  verify_transfer_allowed('transfer-enabled')
  return {'result': 'OK'}

@app.get('/root-key')
async def root_key():
  global transfers_completed
  response = await send_smallstep_secret('secrets/root_ca_key')
  transfers_completed['root_key'] = True
  check_shutdown()
  return response

@app.get('/secureboot-cert')
async def secureboot_cert():
  global transfers_completed
  response = await send_smallstep_secret('certs/secureboot.crt')
  transfers_completed['secureboot_cert'] = True
  check_shutdown()
  return response

@app.get('/secureboot-key')
async def secureboot_key():
  global transfers_completed
  response = await send_smallstep_secret('secrets/secureboot_key')
  transfers_completed['secureboot_key'] = True
  check_shutdown()
  return response

def verify_transfer_allowed() -> Node:
  node = verify_node_jwt()
  node_config = node.get_config()
  if node_config is None:
    raise Forbidden(f'Unable to send the root key to {node.machine_id}. The machine has not been configured.')

  if 'node-role.kubernetes.io/control-plane=true' not in node_config['node-label']:
    raise Forbidden(f'Unable to send the root key to {node.machine_id}. The machine has not been configured as a controle-plane node.')
  if app.config['context']['config']['steppath'] is None:
    raise ServiceUnavailable('The smallstep secrets transfer feature has not been enabled on the boot-server')
  return node

async def send_smallstep_secret(filepath):
  node = verify_transfer_allowed()
  log.info(f'Sending {filepath} to {node.machine_id}')
  return await quart.send_file(app.config['steppath'] / filepath)

def check_shutdown():
  if all(transfers_completed.values()):
    log.info('The remote control-plane node has transferred all step secrets, shutting down so it can take over the registry')
    app.config['context']['shutdown_event'].set()

class JWTVerificationError(Forbidden):
  pass

allowed_jwt_algos = [k for k in jwt.algorithms.get_default_algorithms().keys() if k != 'none']
required_jwt_claims = ['nbf', 'exp', 'aud', 'iss', 'sub']

def get_jwt_auth_header():
  auth_header = quart.request.headers.get('Authorization')
  if auth_header is None:
    raise Forbidden(f'No "Authorization" header was supplied for the path {quart.request.path}')
  return auth_header.removeprefix('Bearer ')

def get_jwt_issuer(token) -> Node | Literal['admin']:
  if token is None:
    raise JWTVerificationError(f'No JWT was provided')
  payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
  issuer = payload['iss']
  return issuer

def verify_jwt(context: Context, token: str, jwk: str | jwt.PyJWK, subject: str):
  payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
  issuer = payload['iss']
  if 'jti' not in payload:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JWT must contain a JTI')
  if context['db'].get(f'used-jtis/{payload['jti']}') is not None:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JTI {payload['jti']} has already been used')
  jwt.decode(token, key=jwk, algorithms=allowed_jwt_algos,
              issuer=issuer, audience=['boot-server'],
              options={'require': required_jwt_claims}, leeway=30)
  context['db'].set(f'used-jtis/{payload['jti']}', '', ttl=int(payload['exp'] - time.time()) + 1)
  if payload['sub'] != subject:
    raise JWTVerificationError(f'Received a JWT for {issuer} with subject "{payload['sub']}", was however expecting the subject "{subject}"')

def verify_admin_jwt():
  token = get_jwt_auth_header()
  subject = f'{quart.request.method} {quart.request.path.lstrip('/')}'
  issuer = get_jwt_issuer(token)
  if issuer != 'admin':
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be admin')
  jwk = app.config['context']['config']['admin_pubkey']
  verify_jwt(app.config['context'], token, jwk, subject)

def verify_bootstrap_jwt():
  token = get_jwt_auth_header()
  subject = f'{quart.request.method} {quart.request.path.lstrip('/')}'
  issuer = get_jwt_issuer(token)
  if issuer != 'bootstrap':
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be bootstrap')
  jwk = app.config['context']['config']['sb_pubkey']
  verify_jwt(app.config['context'], token, jwk, subject)

def verify_node_jwt() -> Node:
  app.config['context']
  token = get_jwt_auth_header()
  subject = f'{quart.request.method} {quart.request.path.lstrip('/')}'
  issuer = get_jwt_issuer(token)
  try:
    node = Node(app.config['context'], uuid.UUID(issuer))
  except ValueError:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be a machine-id')
  jwk = node.get_authn_key()
  if jwk is None:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: No authentication key has been submitted yet')
  verify_jwt(token, jwk, subject)
  return node
