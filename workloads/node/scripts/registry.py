#!/usr/bin/python3

import flask
import os
import sys
import logging
import json
import subprocess
import tempfile

DISK_UUID='caf66bff-edab-4fb1-8ad9-e570be5415d7'

log = logging.getLogger(__name__)
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler(sys.stderr)
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

app = flask.Flask(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

@app.route('/', methods=['GET'])
def get_root():
  flask.abort(404)

@app.route('/images/<path:image_path>')
def get_image(image_path):
  if not app.config['images']:
    flask.abort(503)
  if not os.path.exists(os.path.join(app.config['images'], image_path)):
    flask.abort(404)
  return flask.send_file(os.path.join(app.config['images'], image_path))

@app.route('/registry/health', methods=['GET'])
def get_health():
  return ''

@app.route('/registry/authn-key', methods=['PUT'])
def put_node_authn_key():
  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'Unable to store authn-key, no JWT was included in the query string')
    flask.abort(400)

  try:
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    primary_mac = jwt_data['payload']['iss']
    filename = primary_mac.replace(':', '-') + '.json'
    node_authn_key = json.loads(flask.request.get_data())
  except Exception as e:
    log.error(e)
    flask.abort(400)

  try:
    with tempfile.NamedTemporaryFile(delete_on_close=False) as fp:
      fp.write(json.dumps(node_authn_key, indent=2).encode())
      fp.close()
      subprocess.check_output(
        ['step', 'crypto', 'jwt', 'verify', '--iss', primary_mac, '--aud', 'authn-key', '--key', fp.name],
        input=jwt.encode()
      )
  except Exception as e:
    log.error(e)
    flask.abort(403)

  node_authn_key_persisted = False
  node_state_path = os.path.join(app.config['root'], 'node-states', filename)
  if os.path.exists(node_state_path):
    with open(node_state_path, 'r') as h:
      try:
        node_authn_key_persisted = json.loads(h.read()).get('keys', {}).get('authn', {}).get('persisted', False)
      except Exception as e:
        log.error(e)
        flask.abort(500)

  node_authn_key_path = os.path.join(app.config['root'], 'node-authn-keys', filename)
  if node_authn_key_persisted and os.path.exists(node_authn_key_path):
    with open(node_authn_key_path, 'r') as h:
      existing_node_authn_key = json.loads(h.read())
      if existing_node_authn_key != node_authn_key:
        log.error(f'The authentication key for {primary_mac} does not match the one in the incoming request')
        flask.abort(403)
      else:
        return {'result': 'OK'}
  else:
    with open(node_authn_key_path, 'w') as h:
      try:
        h.write(json.dumps(node_authn_key, indent=2))
      except Exception as e:
        log.error(e)
        flask.abort(500)
    return {'result': 'OK'}

@app.route('/registry/config', methods=['GET'])
def get_node_config():
  filename = verify_jwt('node-config').replace(':', '-') + '.json'
  node_config_path = os.path.join(app.config['root'], 'node-configs', filename)
  if not os.path.exists(node_config_path):
    flask.abort(404)
  with open(node_config_path, 'r') as h:
    try:
      return json.loads(h.read())
    except Exception as e:
      log.error(e)
      flask.abort(500)

@app.route('/registry/state', methods=['PUT'])
def put_node_state():
  filename = verify_jwt('node-state').replace(':', '-') + '.json'
  node_state_path = os.path.join(app.config['root'], 'node-states', filename)
  with open(node_state_path, 'w') as h:
    try:
      node_state = json.loads(flask.request.get_data())
      h.write(json.dumps(node_state, indent=2))
    except Exception as e:
      log.error(e)
      flask.abort(500)

  # Remove the force flag from the disk config once the disk is formatted
  node_config_path = os.path.join(app.config['root'], 'node-configs', filename)
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
    log.error(e)

  return {'result': 'OK'}

transfers_completed = {
  'root_key': False,
  'secureboot_cert': False,
  'secureboot_key': False,
}

@app.route('/registry/transfer-enabled', methods=['GET'])
def transfer_enabled():
  primary_mac = verify_jwt('transfer-enabled')
  if not is_control_plane_node(primary_mac):
    log.error(f'Unable to send the root key to {primary_mac}. The machine has not been configured as a controle-plane node.')
    flask.abort(403)
  if app.config['steppath'] is None:
    flask.abort(503)
  return {'result': 'OK'}

@app.route('/registry/root-key', methods=['GET'])
def root_key():
  response = send_smallstep_secret('secrets/root_ca_key', 'root-key')
  transfers_completed['root_key']=True
  check_shutdown()
  return response

@app.route('/registry/secureboot-cert', methods=['GET'])
def secureboot_cert():
  response = send_smallstep_secret('certs/secureboot.crt', 'secureboot-cert')
  transfers_completed['secureboot_cert']=True
  check_shutdown()
  return response

@app.route('/registry/secureboot-key', methods=['GET'])
def secureboot_key():
  response = send_smallstep_secret('secrets/secureboot_key', 'secureboot-key')
  transfers_completed['secureboot_key']=True
  check_shutdown()
  return response

def send_smallstep_secret(filepath, purpose):
  primary_mac = verify_jwt(purpose)
  if not is_control_plane_node(primary_mac):
    log.error(f'Unable to send the root key to {primary_mac}. The machine has not been configured as a controle-plane node.')
    flask.abort(403)
  if app.config['steppath'] is None:
    flask.abort(503)

  return flask.send_file(os.path.join(app.config['steppath'], filepath))

def is_control_plane_node(primary_mac):
  node_config_path = os.path.join(app.config['root'], 'node-configs', f'{primary_mac.replace(':', '-')}.json')
  if not os.path.exists(node_config_path):
    return False

  try:
    with open(node_config_path, 'r') as h:
      node_config = json.loads(h.read())
  except Exception as e:
    log.error(e)
    return False

  return 'node-role.kubernetes.io/control-plane=true' in node_config['node-label']

def check_shutdown():
  if all(transfers_completed.values()):
    log.info('The remote control-plane node has transferred all step secrets, shutting down so it can take over the registry')
    sys.exit(0)

def verify_jwt(aud):
  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'No JWT was included in the query string')
    flask.abort(400)
  try:
    jwt_data = json.loads(subprocess.check_output(['step', 'crypto', 'jwt', 'inspect', '--insecure'], input=jwt.encode()))
    jwt_primary_mac = jwt_data['payload']['iss']
    node_authn_key_path = os.path.join(app.config['root'], f'node-authn-keys/{jwt_primary_mac.replace(':', '-')}.json')
    if not os.path.exists(node_authn_key_path):
      log.error(f'Unable to verify JWT for {jwt_primary_mac}, no authentication key has been submitted yet')
      flask.abort(400)
    subprocess.check_output(
      ['step', 'crypto', 'jwt', 'verify', '--iss', jwt_primary_mac, '--aud', aud, '--key', node_authn_key_path],
      input=jwt.encode(),
      stderr=sys.stderr
    )
    return jwt_primary_mac
  except Exception as e:
    log.error(e)
    flask.abort(403)

def gunicorn(root, images=False, steppath=None):
  app.config['root'] = root
  app.config['images'] = images
  app.config['steppath'] = steppath
  return app

if __name__ == '__main__':
  app.config['root'] = sys.argv[1]
  app.run()
