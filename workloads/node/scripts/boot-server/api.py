#!/usr/bin/python3

import os, logging, tempfile, shutil, tarfile, tempfile, uuid
from pathlib import Path
import quart
from hypercorn.config import Config
from hypercorn.asyncio import serve
import jwt
from werkzeug.exceptions import HTTPException, NotFound, BadRequest, Forbidden, InternalServerError, ServiceUnavailable
from .registry import Registry, allowed_jwt_algos, required_jwt_claims

DISK_UUID='caf66bff-edab-4fb1-8ad9-e570be5415d7'

log = logging.getLogger(__name__)

app = quart.Quart(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

async def api(ready_event, shutdown_event, registry: Registry,
              host_ip, images: Path, certfile: Path, keyfile: Path, steppath: Path | None=None, promptForNodeConfig=False):
  log.info('Starting registry API')
  global app
  app.config['shutdown_event'] = shutdown_event
  app.config['registry'] = registry
  app.config['images'] = images
  app.config['prompt'] = promptForNodeConfig
  app.config['steppath'] = steppath
  config = Config()
  config.keyfile = keyfile
  config.certfile = certfile
  config.bind = [f'{host_ip}:8020']
  config.accesslog = '-'
  ready_event.set()
  await serve(app, config, shutdown_trigger=shutdown_event.wait)
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
  if not (app.config['images'] / image_path).exists():
    raise NotFound(f'The image {image_path} could not be found')
  log.info(f'Sending {image_path}')
  return await quart.send_file(app.config['images'] / image_path)

@app.put('/images/<path:variant>')
async def put_image(variant):
  issuer = verify_jwt(require_admin=True)
  if 'image' not in quart.request.files:
    raise BadRequest('No image was included in the upload request')
  image_path: Path = app.config['images'] / f'{variant}.uploading'
  image_path_uploaded: Path = app.config['images'] / f'{variant}.uploaded'
  log.info(f'Saving image from {issuer} to {image_path}')
  shutil.rmtree(image_path, ignore_errors=True)
  image_path.mkdir()
  try:
    tmp = tempfile.NamedTemporaryFile(delete_on_close=False)
    try:
      tmp.close()
      await quart.request.files['image'].save(tmp.name)
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
  machine_id = uuid.UUID(payload['iss'])
  submitted_node_authn_key = await quart.request.get_json()
  if submitted_node_authn_key is None:
    raise BadRequest('No authn-key was supplied in the request body')

  node_state = app.config['registry'].get_node_state(machine_id)
  node_authn_key_persisted = False
  if node_state is not None:
    node_authn_key_persisted = node_state.get('keys', {}).get('authn', {}).get('persisted', False)

  existing_node_authn_key = app.config['registry'].get_node_authn_key(machine_id)
  if node_authn_key_persisted and existing_node_authn_key is not None:
    # When a key for an existing node is submitted, validate the JWT using the store key
    verify_jwt()
  else:
    # When a key for a new node is submitted, validate the JWT using the submitted key
    jwt.decode(token, key=jwt.PyJWK.from_dict(submitted_node_authn_key),
                algorithms=allowed_jwt_algos, issuer=payload['iss'], audience=['boot-server'],
                options={'require': required_jwt_claims}, leeway=30)
  log.info(f'Saving authn key for {machine_id}')
  app.config['registry'].update_node_authn_key(machine_id, submitted_node_authn_key)
  return {'result': 'OK'}

@app.get('/machine-ids')
async def get_machine_ids():
  verify_jwt(require_admin=True)
  machine_ids = app.config['registry'].get_all_machine_ids()
  return list(machine_ids)

@app.get('/config')
async def get_node_config():
  machine_id = verify_jwt()
  node_config = app.config['registry'].get_node_config(machine_id)
  if node_config is None:
    raise NotFound(f'The node {machine_id} is not configured, run `bin/configure-node {machine_id}` to do that')
  log.info(f'Sending node-config to {machine_id}')
  return node_config

@app.get('/config/<machine_id>')
async def get_node_config_by_machine_id(machine_id):
  verify_jwt(require_admin=True)
  node_config = app.config['registry'].get_node_config(machine_id)
  if node_config is None:
    raise NotFound(f'Unable to find a node-config for the node {machine_id}')
  return node_config

@app.put('/config/<machine_id>')
async def update_node_config(machine_id):
  verify_jwt(require_admin=True)
  node_config = await quart.request.get_json()
  if node_config is None:
    raise BadRequest('No node-config was supplied in the request body')
  app.config['registry'].update_node_config(machine_id, node_config)
  return {'result': 'OK'}

@app.put('/state')
async def put_node_state():
  machine_id = verify_jwt()
  log.info(f'Saving node-state for {machine_id}')
  node_state = await quart.request.get_json()
  app.config['registry'].update_node_state(machine_id, node_state)
  node_config = app.config['registry'].get_node_config(machine_id)
  if node_config is not None:
    if node_config['disk'].get('force', False) == True:
      selected_block_device = next(
        filter(lambda bd: bd['devpath'] == node_config['disk']['devpath'], node_state['blockdevices']),
        None
      )
      if selected_block_device.get('partitions', {}).get('partitiontable', {}).get('id', None).lower() == DISK_UUID:
        del node_config['disk']['force']
        app.config['registry'].update_node_config(machine_id, node_config)
  return {'result': 'OK'}

@app.get('/state/<machine_id>')
async def get_node_state_by_machine_id(machine_id):
  verify_jwt(require_admin=True)
  node_state = app.config['registry'].get_node_state(machine_id)
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

def verify_transfer_allowed():
  machine_id = verify_jwt()
  node_config = app.config['registry'].get_node_config(machine_id)
  if node_config is None:
    return False

  if 'node-role.kubernetes.io/control-plane=true' not in node_config['node-label']:
    raise Forbidden(f'Unable to send the root key to {machine_id}. The machine has not been configured as a controle-plane node.')
  if app.config['steppath'] is None:
    raise ServiceUnavailable('The smallstep secrets transfer feature has not been enabled on the boot-server')
  return machine_id

async def send_smallstep_secret(filepath):
  machine_id = verify_transfer_allowed()
  log.info(f'Sending {filepath} to {machine_id}')
  return await quart.send_file(app.config['steppath'] / filepath)

def check_shutdown():
  if all(transfers_completed.values()):
    log.info('The remote control-plane node has transferred all step secrets, shutting down so it can take over the registry')
    app.config['shutdown_event'].set()

def verify_jwt(require_admin=False):
  return app.config['registry'].verify_jwt(get_jwt_auth_header(), f'{quart.request.method} {quart.request.path.lstrip('/')}', require_admin)

def get_jwt_auth_header():
  auth_header = quart.request.headers.get('Authorization')
  if auth_header is None:
    raise Forbidden(f'No "Authorization" header was supplied for the path {quart.request.path}')
  return auth_header.removeprefix('Bearer ')
