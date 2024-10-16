#!/usr/bin/python3

import flask
import os
from os import path
import sys
import logging
import json
import subprocess
import tempfile
import re
import shutil
import tarfile
import time
import tempfile
from collections import namedtuple

DISK_UUID='caf66bff-edab-4fb1-8ad9-e570be5415d7'

log = logging.getLogger(__name__)
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler(sys.stderr)
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

app = flask.Flask(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

invalid_filename_chars = re.compile(r'[^a-zA-Z0-9 _-]')

@app.get('/')
def get_root():
  flask.abort(404)

@app.get('/images/<path:image_path>')
def get_image(image_path):
  if not os.path.exists(path.join(app.config['images'], image_path)):
    flask.abort(404)
  log.info(f'Sending {image_path}')
  return flask.send_file(path.join(app.config['images'], image_path))

@app.put('/images/<path:variant>')
def put_image(variant):
  (issuer, issuer_filename) = verify_jwt('image-upload', require_admin=True)
  if 'image' not in flask.request.files:
    flask.abort(400)
  image_path = path.join(app.config['images'], f'{variant}.upload')
  log.info(f'Saving image from {issuer} to {image_path}')
  shutil.rmtree(image_path, ignore_errors=True)
  os.mkdir(image_path)
  try:
    tmp = tempfile.NamedTemporaryFile(delete_on_close=False)
    try:
      tmp.close()
      flask.request.files['image'].save(tmp.name)
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
def get_health():
  return ''

@app.put('/registry/authn-key')
def put_node_authn_key():
  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'Unable to store authn-key, no JWT was included in the query string')
    flask.abort(400)

  try:
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    issuer = jwt_data['payload']['iss']
    issuer_filename = invalid_filename_chars.sub('_', issuer) + '.json'
    node_authn_key = json.loads(flask.request.get_data())
  except Exception as e:
    log.exception(e)
    flask.abort(400)

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
    flask.abort(403)

  node_authn_key_persisted = False
  node_state_path = path.join(app.config['root'], 'node-states', issuer_filename)
  if os.path.exists(node_state_path):
    with open(node_state_path, 'r') as h:
      try:
        node_authn_key_persisted = json.loads(h.read()).get('keys', {}).get('authn', {}).get('persisted', False)
      except Exception as e:
        log.exception(e)
        flask.abort(500)

  node_authn_key_path = path.join(app.config['root'], 'node-authn-keys', issuer_filename)
  if node_authn_key_persisted and os.path.exists(node_authn_key_path):
    with open(node_authn_key_path, 'r') as h:
      existing_node_authn_key = json.loads(h.read())
      if existing_node_authn_key != node_authn_key:
        log.error(f'The authentication key for {issuer} does not match the one in the incoming request')
        flask.abort(403)
      else:
        return {'result': 'OK'}
  else:
    log.info(f'Saving authn key for {issuer}')
    with open(node_authn_key_path, 'w') as h:
      try:
        h.write(json.dumps(node_authn_key, indent=2))
      except Exception as e:
        log.exception(e)
        flask.abort(500)
    return {'result': 'OK'}

@app.get('/registry/config')
def get_node_config():
  (issuer, issuer_filename) = verify_jwt('node-config')
  node_config_path = path.join(app.config['root'], 'node-configs', issuer_filename)
  if not os.path.exists(node_config_path):
    flask.abort(404)
  with open(node_config_path, 'r') as h:
    log.info(f'Sending node-config to {issuer}')
    try:
      return json.loads(h.read())
    except Exception as e:
      log.exception(e)
      flask.abort(500)

@app.route('/registry/state', methods=['PUT'])
def put_node_state():
  (issuer, issuer_filename) = verify_jwt('node-state')
  node_state_path = path.join(app.config['root'], 'node-states', issuer_filename)
  with open(node_state_path, 'w') as h:
    log.info(f'Saving node-state for {issuer}')
    try:
      node_state = json.loads(flask.request.get_data())
      h.write(json.dumps(node_state, indent=2))
    except Exception as e:
      log.exception(e)
      flask.abort(500)

  # Remove the force flag from the disk config once the disk is formatted
  node_config_path = path.join(app.config['root'], 'node-configs', issuer_filename)
  try:
    if os.path.exists(node_config_path):
      with open(node_config_path, 'r') as h:
        node_config = json.loads(h.read())
      if node_config['disk'].get('force', False) == True:
        selected_block_device = next(
          filter(lambda bd: bd['devpath'] == node_config['disk']['devpath'], node_state['blockdevices']),
          None
        )
        if selected_block_device.get('partitions', {}).get('partitiontable', {}).get('id', None).lower() == DISK_UUID:
          del node_config['disk']['force']
          with open(node_config_path, 'w') as h:
            h.write(json.dumps(node_config, indent=2))
  except Exception as e:
    log.exception(e)

  return {'result': 'OK'}

transfers_completed = {
  'root_key': False,
  'secureboot_cert': False,
  'secureboot_key': False,
}

@app.get('/registry/transfer-enabled')
def transfer_enabled():
  (issuer, issuer_filename) = verify_jwt('transfer-enabled')
  if not is_control_plane_node(issuer):
    log.error(f'Unable to send the root key to {issuer}. The machine has not been configured as a controle-plane node.')
    flask.abort(403)
  if app.config['steppath'] is None:
    flask.abort(503)
  return {'result': 'OK'}

@app.get('/registry/root-key')
def root_key():
  response = send_smallstep_secret('secrets/root_ca_key', 'root-key')
  transfers_completed['root_key']=True
  check_shutdown()
  return response

@app.get('/registry/secureboot-cert')
def secureboot_cert():
  response = send_smallstep_secret('certs/secureboot.crt', 'secureboot-cert')
  transfers_completed['secureboot_cert']=True
  check_shutdown()
  return response

@app.get('/registry/secureboot-key')
def secureboot_key():
  response = send_smallstep_secret('secrets/secureboot_key', 'secureboot-key')
  transfers_completed['secureboot_key']=True
  check_shutdown()
  return response

def send_smallstep_secret(filepath, purpose):
  (issuer, issuer_filename) = verify_jwt(purpose)
  if not is_control_plane_node(issuer_filename):
    log.error(f'Unable to send the root key to {issuer}. The machine has not been configured as a controle-plane node.')
    flask.abort(403)
  if app.config['steppath'] is None:
    flask.abort(503)

  log.info(f'Sending {filepath} to {issuer}')
  return flask.send_file(path.join(app.config['steppath'], filepath))

def is_control_plane_node(issuer_filename):
  node_config_path = path.join(app.config['root'], 'node-configs', issuer_filename)
  if not os.path.exists(node_config_path):
    return False

  try:
    with open(node_config_path, 'r') as h:
      node_config = json.loads(h.read())
  except Exception as e:
    log.exception(e)
    return False

  return 'node-role.kubernetes.io/control-plane=true' in node_config['node-label']

def check_shutdown():
  if all(transfers_completed.values()):
    log.info('The remote control-plane node has transferred all step secrets, shutting down so it can take over the registry')
    sys.exit(0)

used_jtis = set()
UsedJTI = namedtuple('UsedJTI', ['expires', 'id'])

def verify_jwt(purpose, require_admin=False):
  global used_jtis
  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'No JWT was included in the query string')
    flask.abort(400)
  try:
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    if 'jti' not in jwt_data['payload']:
      log.error(f'Unable to verify JWT for {issuer}, JWT must contain a JTI')
      flask.abort(400)
    jti = jwt_data['payload']['jti']
    if any(map(lambda used_jti: used_jti.id == jti, used_jtis)):
      log.error(f'Unable to verify JWT for {issuer}, the JTI {jti} has already been used')
      flask.abort(400)
    issuer = jwt_data['payload']['iss']
    if require_admin:
      if issuer != 'admin':
        log.error(f'Unable to verify JWT for {issuer}, issuer must be admin')
        flask.abort(400)
      issuer_filename = None
      node_authn_key_path = app.config['admin-pubkey']
    else:
      issuer_filename = invalid_filename_chars.sub('_', issuer) + '.json'
      node_authn_key_path = path.join(app.config['root'], f'node-authn-keys/{issuer_filename}')
    if not os.path.exists(node_authn_key_path):
      log.error(f'Unable to verify JWT for {issuer}, no authentication key has been submitted yet')
      flask.abort(400)
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
    flask.abort(403)

def gunicorn(root, images=None, admin_pubkey=None, steppath=None):
  app.config['root'] = root
  app.config['images'] = images if images is not None else path.join(root, 'images')
  app.config['admin-pubkey'] = admin_pubkey if admin_pubkey is not None else path.join(root, 'admin.pub')
  app.config['steppath'] = steppath
  return app

if __name__ == '__main__':
  app.config['root'] = sys.argv[1]
  app.run()
