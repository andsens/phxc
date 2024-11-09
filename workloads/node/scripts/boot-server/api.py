#!/usr/bin/python3

import asyncio, json, os, logging, tempfile, tarfile, tempfile, uuid, datetime
from pathlib import Path
import quart
from hypercorn.config import Config
from hypercorn.asyncio import serve
from werkzeug.exceptions import HTTPException, NotFound, BadRequest, Forbidden, InternalServerError, ServiceUnavailable
import jwt
from .node import Node
from .image import Image, ImageFile
import time, uuid
import macaddress
from typing import Literal
import jwt
import jwt.algorithms
from .node import Node
from .boot_events import authn_key_submitted, image_upload_completed, initial_node_state_reported, final_node_state_reported
from . import BuildMeta, Context, NodeState
from .dbobject import load_or_none

DISK_UUID='caf66bff-edab-4fb1-8ad9-e570be5415d7'

log = logging.getLogger(__name__)

app = quart.Quart(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

async def api(ctx: Context, ready_event: asyncio.Event):
  log.info('Starting registry API')
  global app
  app.config['ctx'] = ctx
  config = Config()
  config.bind = [f'{ctx.host_ip}:8021']
  config.accesslog = '-'
  ready_event.set()
  await serve(app, config, shutdown_trigger=ctx.shutdown_event.wait)
  log.info('Closed registry API')

@app.errorhandler(HTTPException)
def handle_http_exception(e: HTTPException):
  log.error(e.description)
  return e.description or '', e.code or 500

@app.errorhandler(Exception)
def handle_other_exceptions(e: Exception):
  log.exception(e)
  return 'Internal server error', 500

@app.get('/')
async def get_root():
  raise

@app.get('/images/<path:image_path>')
async def get_image(image_path):
  if not (app.config['ctx'].images / image_path).exists():
    raise NotFound(f'The image {image_path} could not be found')
  log.info(f'Sending {image_path}')
  return await quart.send_file(app.config['ctx'].images / image_path)

@app.put('/images')
async def put_image():
  verify_bootstrap_jwt()
  ctx: Context = app.config['ctx']
  if 'image' not in await quart.request.files:
    raise BadRequest('No image was included in the upload request')
  image = Image.new(ctx)
  try:
    files = await quart.request.files
    metadata: BuildMeta = json.loads(files['meta.json'])
    image.abspath.mkdir()
    image.variant = metadata['variant']
    image.boot_file = image.files.new(metadata['boot-file'])
    image.build_date = datetime.datetime.fromisoformat(metadata['build-date'])
    for (name, sha256sum) in metadata['sha256sums'].items():
      image.files[name].sha256sum = sha256sum
    for (name, authentihashset) in metadata['authentihashes'].items():
      image.files[name].authentihashset = authentihashset
    for (name, file) in files.items():
      if name != 'meta.json':
        file.save(image.abspath / name)
    image_upload_completed(ctx, image)
  except Exception as e:
    image.delete()
    raise InternalServerError(str(e))
  return {'result': 'OK'}

@app.get('/health')
async def get_health():
  return ''

@app.put('/authn-key')
async def put_node_authn_key():
  token = get_jwt_auth_header()
  ctx: Context = app.config['ctx']

  payload = jwt.decode(token, algorithms=allowed_jwt_algos, options={'verify_signature': False, 'require': required_jwt_claims})
  submitted_key = await quart.request.get_json()
  if submitted_key is None:
    raise BadRequest('No authn-key was supplied in the request body')

  machine_id = uuid.UUID(payload['iss'])
  node = Node.get_by_machine_id(ctx, machine_id)
  if node is None or not getattr(node, 'state', {}).get('keys', {}).get('authn', {}).get('persisted', False):
    # When a key for a new node is submitted, validate the JWT using the submitted key
    jwt.decode(token, key=jwt.PyJWK.from_dict(submitted_key),
              algorithms=allowed_jwt_algos, issuer=payload['iss'], audience=['boot-server'],
              options={'require': required_jwt_claims}, leeway=30)
    ctx.db.set(f'{ctx.dbprefix}/tentative-authn-keys/{machine_id}', json.dumps(submitted_key, indent=2), ctx.tentative_authn_key_ttl)
  else:
    # When a key for an existing node is submitted, validate the JWT using the stored key
    verify_node_jwt(ctx)
    node.authn_key = submitted_key
  authn_key_submitted(ctx, node or machine_id)
  return {'result': 'OK'}

@app.get('/machine-ids')
async def get_machine_ids():
  verify_admin_jwt()
  machine_ids = Node.get_all(app.config['ctx'])
  return list(machine_ids)

@app.get('/config')
async def get_node_config():
  ctx: Context = app.config['ctx']
  machine_id = verify_node_jwt(ctx)
  node = Node.get_by_machine_id(ctx, machine_id)
  if node is None:
    raise NotFound(f'Unable to find node with the machine-id {machine_id}')
  node_config = node.get_config()
  if node_config is None:
    raise NotFound(f'The node {node} is not configured, run `bin/configure-node {node.machine_id}` to do that')
  log.info(f'Sending node-config to {node.machine_id}')
  return node_config

@app.get('/config/<machine_id>')
async def get_node_config_by_machine_id(machine_id):
  verify_admin_jwt()
  node = Node.get_by_machine_id(app.config['ctx'], uuid.UUID(machine_id))
  if node is None:
    raise NotFound(f'Unable to find node with the machine-id {machine_id}')
  node_config = node.get_config()
  if node_config is None:
    raise NotFound(f'Unable to find a node-config for the node {machine_id}')
  return node_config

@app.put('/config/<machine_id>')
async def update_node_config(machine_id):
  verify_admin_jwt()
  node = Node.get_by_machine_id(app.config['ctx'], uuid.UUID(machine_id))
  if node is None:
    raise NotFound(f'Unable to find node with the machine-id {machine_id}')
  new_node_config = await quart.request.get_json()
  if new_node_config is None:
    raise BadRequest('No node-config was supplied in the request body')
  node.set_config(new_node_config)
  return {'result': 'OK'}

@app.put('/state')
async def put_node_state():
  ctx: Context = app.config['ctx']
  machine_id = verify_node_jwt(ctx, allow_tentative_keys=True)
  new_node_state: NodeState = await quart.request.get_json()
  mac = macaddress.MAC(new_node_state['primary-mac'])
  node = Node.get_by_mac(ctx, mac)
  if node is None:
    raise NotFound(f'Unable to find a node with the mac "{mac}"')
  node.machine_id = machine_id

  tentative_authn_key = load_or_none(ctx, f'{ctx.dbprefix}/tentative-authn-keys/{machine_id}', json.loads)
  if tentative_authn_key is not None:
    log.info(f'Persisting tentative authn-key for {node}')
    node.authn_key = tentative_authn_key
    ctx.db.delete(f'{ctx.dbprefix}/tentative-authn-keys/{machine_id}')

  log.info(f'Saving node-state for {node.machine_id}')
  node.set_state(new_node_state)
  node_config = node.get_config()
  if new_node_state['report-phase'] == 'initial':
    initial_node_state_reported(app.config['ctx'], node, new_node_state)
  else:
    final_node_state_reported(app.config['ctx'], node, new_node_state)
  if node_config is not None:
    if node_config['disk'].get('force', False) == True:
      selected_block_device = next(
        filter(lambda bd: bd['devpath'] == node_config['disk']['devpath'], new_node_state['blockdevices']),
        None
      )
      if (selected_block_device or {}).get('partitions', {}).get('partitiontable', {}).get('id', None).lower() == DISK_UUID:
        del node_config['disk']['force']
        node.set_config(node_config)
  return {'result': 'OK'}

@app.get('/state/<machine_id>')
async def get_node_state_by_machine_id(machine_id):
  verify_admin_jwt()
  node = Node.get_by_machine_id(app.config['ctx'], uuid.UUID(machine_id))
  if node is None:
    raise NotFound(f'Unable to find node with the machine-id {machine_id}')
  node_state = node.get_state()
  if node_state is None:
    raise NotFound(f'Unable to find a node-state for the node {node}')
  return node_state

class JWTVerificationError(Forbidden):
  pass

allowed_jwt_algos = [k for k in jwt.algorithms.get_default_algorithms().keys() if k != 'none']
required_jwt_claims = ['nbf', 'exp', 'aud', 'iss', 'sub']

def get_jwt_auth_header():
  auth_header = quart.request.headers.get('Authorization')
  if auth_header is None:
    raise Forbidden(f'No "Authorization" header was supplied for the path {quart.request.path}')
  return auth_header.removeprefix('Bearer ')

def get_jwt_issuer(token) -> str:
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
  if context.db.get(f'used-jtis/{payload['jti']}') is not None:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: The JTI {payload['jti']} has already been used')
  jwt.decode(token, key=jwk, algorithms=allowed_jwt_algos,
              issuer=issuer, audience=['boot-server'],
              options={'require': required_jwt_claims}, leeway=30)
  context.db.set(f'used-jtis/{payload['jti']}', '', ttl=int(payload['exp'] - time.time()) + 1)
  if payload['sub'] != subject:
    raise JWTVerificationError(f'Received a JWT for {issuer} with subject "{payload['sub']}", was however expecting the subject "{subject}"')

def verify_admin_jwt():
  ctx: Context = app.config['ctx']
  token = get_jwt_auth_header()
  subject = f'{quart.request.method} {quart.request.path.lstrip('/')}'
  issuer = get_jwt_issuer(token)
  if issuer != 'admin':
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be admin')
  jwk = ctx.admin_pubkey
  verify_jwt(ctx, token, jwk, subject)

def verify_bootstrap_jwt():
  ctx: Context = app.config['ctx']
  token = get_jwt_auth_header()
  subject = f'{quart.request.method} {quart.request.path.lstrip('/')}'
  issuer = get_jwt_issuer(token)
  if issuer != 'bootstrap':
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be bootstrap')
  jwk = ctx.sb_pubkey
  verify_jwt(ctx, token, jwk, subject)

def verify_node_jwt(ctx: Context, allow_tentative_keys = False) -> uuid.UUID:
  token = get_jwt_auth_header()
  subject = f'{quart.request.method} {quart.request.path.lstrip('/')}'
  issuer = get_jwt_issuer(token)
  try:
    machine_id = uuid.UUID(issuer)
  except ValueError:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: Issuer must be a machine-id')

  jwk = None
  node = Node.get_by_machine_id(ctx, machine_id)
  if node is not None:
    jwk = node.authn_key
  elif allow_tentative_keys:
    jwk = load_or_none(ctx, f'{ctx.dbprefix}/tentative-authn-keys/{machine_id}', json.loads)
  if jwk is None:
    raise JWTVerificationError(f'Unable to verify JWT for {issuer}: No authentication key has been submitted yet')
  verify_jwt(app.config['ctx'], token, jwk, subject)
  return machine_id
