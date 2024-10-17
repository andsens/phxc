#!/usr/bin/python3

import os, sys, logging, json, subprocess, tempfile, re, shutil, tarfile, time, tempfile, collections
from pathlib import Path
import quart
from hypercorn.config import Config
from hypercorn.asyncio import serve


DISK_UUID='caf66bff-edab-4fb1-8ad9-e570be5415d7'

log = logging.getLogger(__name__)

app = quart.Quart(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

async def registry(ready_event, shutdown_event, host_ip, root: Path, images: Path, certfile: Path, keyfile: Path, admin_pubkey: Path, steppath: Path | None=None):
  log.info('Starting node registry')
  global app
  app.config['root'] = root
  app.config['images'] = images
  app.config['admin-pubkey'] = admin_pubkey
  app.config['steppath'] = steppath
  app.config['shutdown_event'] = shutdown_event
  config = Config()
  config.keyfile = keyfile
  config.certfile = certfile
  config.bind = [f'{host_ip}:8020']
  config.accesslog = '-'
  ready_event.set()
  await serve(app, config, shutdown_trigger=shutdown_event.wait)
  log.info('Closed node registry')

transfers_completed = {
  'root_key': False,
  'secureboot_cert': False,
  'secureboot_key': False,
}
invalid_filename_chars = re.compile(r'[^a-zA-Z0-9 _-]')

@app.get('/')
async def get_root():
  quart.abort(404)

@app.get('/images/<path:image_path>')
async def get_image(image_path):
  if not (app.config['images'] / image_path).exists():
    quart.abort(404)
  log.info(f'Sending {image_path}')
  return await quart.send_file(app.config['images'] / image_path)

@app.put('/images/<path:variant>')
async def put_image(variant):
  (issuer, issuer_filename) = verify_jwt('image-upload', require_admin=True)
  if 'image' not in quart.request.files:
    quart.abort(400)
  image_path: Path = app.config['images'] / f'{variant}.upload'
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
      raise
  except Exception as e:
    shutil.rmtree(image_path, ignore_errors=True)
    log.exception(e)
  return {'result': 'OK'}

@app.get('/registry/health')
async def get_health():
  return ''

@app.put('/registry/authn-key')
async def put_node_authn_key():
  jwt = quart.request.args.get('jwt')
  if jwt is None:
    log.error(f'Unable to store authn-key, no JWT was included in the query string')
    quart.abort(400)

  try:
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    issuer = jwt_data['payload']['iss']
    issuer_filename = invalid_filename_chars.sub('_', issuer) + '.json'
    node_authn_key = await quart.request.get_json()
  except Exception as e:
    log.exception(e)
    quart.abort(400)

  try:
    with tempfile.NamedTemporaryFile(delete_on_close=False) as fp:
      fp.write(json.dumps(node_authn_key, indent=2).encode())
      fp.close()
      subprocess.check_output(
        ['step', 'crypto', 'jwt', 'verify', '--iss', issuer, '--aud', 'authn-key', '--key', fp.name],
        input=jwt.encode()
      )
  except Exception as e:
    log.exception(e)
    quart.abort(403)

  node_authn_key_persisted = False
  node_state_path: Path = app.config['root'] / 'node-states' / issuer_filename
  if node_state_path.exists():
    with node_state_path.open('r') as h:
      try:
        node_authn_key_persisted = json.loads(h.read()).get('keys', {}).get('authn', {}).get('persisted', False)
      except Exception as e:
        log.exception(e)
        quart.abort(500)

  node_authn_key_path: Path = app.config['root'] / 'node-authn-keys' / issuer_filename
  if node_authn_key_persisted and node_authn_key_path.exists():
    with node_authn_key_path.open('r') as h:
      existing_node_authn_key = json.loads(h.read())
      if existing_node_authn_key != node_authn_key:
        log.error(f'The authentication key for {issuer} does not match the one in the incoming request')
        quart.abort(403)
      else:
        return {'result': 'OK'}
  else:
    log.info(f'Saving authn key for {issuer}')
    with node_authn_key_path.open('w') as h:
      try:
        h.write(json.dumps(node_authn_key, indent=2))
      except Exception as e:
        log.exception(e)
        quart.abort(500)
    return {'result': 'OK'}

@app.get('/registry/config')
async def get_node_config():
  (issuer, issuer_filename) = verify_jwt('node-config')
  node_config_path: Path = app.config['root'] / 'node-configs' / issuer_filename
  if not node_config_path.exists():
    quart.abort(404)
  with node_config_path.open('r') as h:
    log.info(f'Sending node-config to {issuer}')
    try:
      return json.loads(h.read())
    except Exception as e:
      log.exception(e)
      quart.abort(500)

@app.route('/registry/state', methods=['PUT'])
async def put_node_state():
  (issuer, issuer_filename) = verify_jwt('node-state')
  node_state_path: Path = app.config['root'] / 'node-states' / issuer_filename
  with node_state_path.open('w') as h:
    log.info(f'Saving node-state for {issuer}')
    try:
      node_state = await quart.request.get_json()
      h.write(json.dumps(node_state, indent=2))
    except Exception as e:
      log.exception(e)
      quart.abort(500)

  # Remove the force flag from the disk config once the disk is formatted
  node_config_path: Path = app.config['root'] / 'node-configs' / issuer_filename
  try:
    if node_config_path.exists():
      with node_config_path.open('r') as h:
        node_config = json.loads(h.read())
      if node_config['disk'].get('force', False) == True:
        selected_block_device = next(
          filter(lambda bd: bd['devpath'] == node_config['disk']['devpath'], node_state['blockdevices']),
          None
        )
        if selected_block_device.get('partitions', {}).get('partitiontable', {}).get('id', None).lower() == DISK_UUID:
          del node_config['disk']['force']
          with node_config_path.open('w') as h:
            h.write(json.dumps(node_config, indent=2))
  except Exception as e:
    log.exception(e)

  return {'result': 'OK'}

@app.get('/registry/transfer-enabled')
async def transfer_enabled():
  verify_transfer_allowed('transfer-enabled')
  return {'result': 'OK'}

@app.get('/registry/root-key')
async def root_key():
  global transfers_completed
  response = send_smallstep_secret('secrets/root_ca_key', 'root-key')
  transfers_completed['root_key'] = True
  check_shutdown()
  return response

@app.get('/registry/secureboot-cert')
async def secureboot_cert():
  global transfers_completed
  response = send_smallstep_secret('certs/secureboot.crt', 'secureboot-cert')
  transfers_completed['secureboot_cert'] = True
  check_shutdown()
  return response

@app.get('/registry/secureboot-key')
async def secureboot_key():
  global transfers_completed
  response = send_smallstep_secret('secrets/secureboot_key', 'secureboot-key')
  transfers_completed['secureboot_key'] = True
  check_shutdown()
  return response

def verify_transfer_allowed(purpose):
  (issuer, issuer_filename) = verify_jwt(purpose)
  node_config_path: Path = app.config['root'] / 'node-configs' / issuer_filename
  if not node_config_path.exists():
    return False
  try:
    with node_config_path.open('r') as h:
      node_config = json.loads(h.read())
  except Exception as e:
    log.exception(e)
    quart.abort(403)

  if 'node-role.kubernetes.io/control-plane=true' not in node_config['node-label']:
    log.error(f'Unable to send the root key to {issuer}. The machine has not been configured as a controle-plane node.')
    quart.abort(403)
  if app.config['steppath'] is None:
    quart.abort(503)
  return issuer

def send_smallstep_secret(filepath, purpose):
  issuer = verify_transfer_allowed(purpose)
  log.info(f'Sending {filepath} to {issuer}')
  return quart.send_file(app.config['steppath'] / filepath)

def check_shutdown():
  if all(transfers_completed.values()):
    log.info('The remote control-plane node has transferred all step secrets, shutting down so it can take over the registry')
    app.config['shutdown_event'].set()

used_jtis = set()
UsedJTI = collections.namedtuple('UsedJTI', ['expires', 'id'])

def verify_jwt(purpose, require_admin=False):
  global used_jtis
  jwt = quart.request.args.get('jwt')
  if jwt is None:
    log.error(f'No JWT was included in the query string')
    quart.abort(400)
  try:
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    if 'jti' not in jwt_data['payload']:
      log.error(f'Unable to verify JWT for {issuer}, JWT must contain a JTI')
      quart.abort(400)
    jti = jwt_data['payload']['jti']
    if any(map(lambda used_jti: used_jti.id == jti, used_jtis)):
      log.error(f'Unable to verify JWT for {issuer}, the JTI {jti} has already been used')
      quart.abort(400)
    issuer = jwt_data['payload']['iss']
    if require_admin:
      if issuer != 'admin':
        log.error(f'Unable to verify JWT for {issuer}, issuer must be admin')
        quart.abort(400)
      issuer_filename = None
      node_authn_key_path: Path = app.config['admin-pubkey']
    else:
      issuer_filename = Path(invalid_filename_chars.sub('_', issuer) + '.json')
      node_authn_key_path: Path = app.config['root'] / 'node-authn-keys' / issuer_filename
    if not node_authn_key_path.exists():
      log.error(f'Unable to verify JWT for {issuer}, no authentication key has been submitted yet')
      quart.abort(400)
    subprocess.check_output(
      ['step', 'crypto', 'jwt', 'verify', '--iss', issuer, '--aud', 'boot-server', '--key', node_authn_key_path],
      input=jwt.encode(),
      stderr=sys.stderr
    )
    used_jtis.add(UsedJTI(jwt_data['payload']['exp'], jwt_data['payload']['jti']))
    if jwt_data['payload']['sub'] != purpose:
      raise Exception(f'Received a JWT for {issuer} with subject "{jwt_data['payload']['sub']}", was however expecting the subject "{purpose}"')
    used_jtis = set(filter(lambda used_jti: used_jti.expires < time.time(), used_jtis))
    return (issuer, issuer_filename)
  except Exception as e:
    log.exception(e)
    quart.abort(403)
