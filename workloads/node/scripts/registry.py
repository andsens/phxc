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
  flask.abort(405)

@app.route('/images/<path:image_path>')
def send_report(image_path):
  if not app.config['enable_images']:
    flask.abort(500)
  if not os.path.exists(os.path.join(app.config['root'], 'images', image_path)):
    flask.abort(404)
  return flask.send_file(os.path.join(app.config['root'], 'images', image_path))

@app.route('/registry/health', methods=['GET'])
def get_health():
  return ''

@app.route('/registry/node-authn-keys/<path:node_mac_filename>', methods=['PUT'])
def put_node_authn_key(node_mac_filename):
  primary_mac = node_mac_filename.removesuffix('.json').replace('-', ':')
  try:
    node_authn_key = json.loads(flask.request.get_data())
  except Exception as e:
    log.error(e)
    flask.abort(400)

  node_authn_key_persisted = False
  node_state_path = os.path.join(app.config['root'], 'node-states', node_mac_filename)
  if os.path.exists(node_state_path):
    with open(node_state_path, 'r') as h:
      try:
        node_authn_key_persisted = json.loads(h.read()).get('keys', {}).get('authn', {}).get('persisted', False)
      except Exception as e:
        log.error(e)
        flask.abort(500)

  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'Unable to store authn key for {primary_mac}, no JWT was included in the query string')
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

  node_authn_key_path = os.path.join(app.config['root'], 'node-authn-keys', node_mac_filename)
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


@app.route('/registry/node-configs/<path:node_mac_filename>', methods=['GET'])
def get_node_config(node_mac_filename):
  primary_mac = node_mac_filename.removesuffix('.json').replace('-', ':')
  node_authn_key_path = os.path.join(app.config['root'], 'node-authn-keys', node_mac_filename)
  if not os.path.exists(node_authn_key_path):
    log.error(f'Unable to send node-config to {primary_mac}, no authentication key has been submitted yet')
    flask.abort(400)

  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'Unable to send node-config to {primary_mac}, no JWT was included in the query string')
    flask.abort(400)
  try:
    subprocess.check_output(
      ['step', 'crypto', 'jwt', 'verify', '--iss', primary_mac, '--aud', 'node-config', '--key', node_authn_key_path],
      input=jwt.encode()
    )
  except Exception as e:
    log.error(e)
    flask.abort(403)

  node_config_path = os.path.join(app.config['root'], 'node-configs', node_mac_filename)
  if not os.path.exists(node_config_path):
    flask.abort(404)

  with open(node_config_path, 'r') as h:
    try:
      return json.loads(h.read())
    except Exception as e:
      log.error(e)
      flask.abort(500)


@app.route('/registry/node-states/<path:node_mac_filename>', methods=['PUT'])
def put_node_state(node_mac_filename):
  primary_mac = node_mac_filename.removesuffix('.json').replace('-', ':')
  node_authn_key_path = os.path.join(app.config['root'], 'node-authn-keys', node_mac_filename)
  if not os.path.exists(node_authn_key_path):
    log.error(f'Unable to store node-state for {primary_mac}, no authentication key has been submitted yet')
    flask.abort(400)

  jwt = flask.request.args.get('jwt')
  if jwt is None:
    log.error(f'Unable to store node-state for {primary_mac}, no JWT was included in the query string')
    flask.abort(400)
  try:
    subprocess.check_output(
      ['step', 'crypto', 'jwt', 'verify', '--iss', primary_mac, '--aud', 'node-state', '--key', node_authn_key_path],
      input=jwt.encode()
    )
  except Exception as e:
    log.error(e)
    flask.abort(403)

  node_state_path = os.path.join(app.config['root'], 'node-states', node_mac_filename)
  with open(node_state_path, 'w') as h:
    try:
      node_state = json.loads(flask.request.get_data())
      h.write(json.dumps(node_state, indent=2))
    except Exception as e:
      log.error(e)
      flask.abort(500)

  # Remove the force flag from the disk config once the disk is formatted
  node_config_path = os.path.join(app.config['root'], 'node-configs', node_mac_filename)
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


def gunicorn(root, enable_images=False):
  app.config['root'] = root
  app.config['enable_images'] = enable_images
  return app

if __name__ == '__main__':
  app.config['root'] = sys.argv[1]
  app.run()
