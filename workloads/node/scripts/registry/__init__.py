#!/usr/bin/python3

import flask
import os
import sys
from Crypto.PublicKey import RSA
from Crypto.Signature import pkcs1_15
from Crypto.Hash import SHA256, HMAC
from Crypto.Cipher import AES, PKCS1_OAEP
from Crypto.Random import get_random_bytes
from Crypto.Util.Padding import pad
import logging
import json
import base64


log = logging.getLogger(__name__)
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler(sys.stderr)
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

app = flask.Flask(__name__)
app.config['DEBUG'] = os.getenv('LOGLEVEL', 'INFO').upper() == 'DEBUG'

@app.route('/', methods=['GET'])
def root_get():
  flask.abort(405)

@app.route('/images/<path:image_path>')
def send_report(image_path):
  if not app.config['enable_images']:
    flask.abort(500)
  return flask.send_file(os.path.join(app.config['root'], 'images', image_path))

@app.route('/registry/node-config/<path:node_mac_filename>', methods=['GET'])
def get_node_config(node_mac_filename):
  node_config_path = os.path.join(app.config['root'], 'node-config', node_mac_filename)
  node_state_path = os.path.join(app.config['root'], 'node-state', node_mac_filename)
  with open(node_state_path, 'r') as h:
    node_key = RSA.import_key(json.loads(h.read())['node-key'])

  with open(node_config_path, 'r') as h:
    try:
      raw_json = h.read()
      json.loads(raw_json)  # Make sure we are sending back valid JSON
    except Exception as e:
      log.error(e)
      flask.abort(500)

  aes_key = get_random_bytes(32)
  aes_iv = get_random_bytes(16)
  hmac_key = get_random_bytes(16)

  enc = AES.new(aes_key, AES.MODE_CBC, iv=aes_iv)
  encrypted_config = enc.encrypt(pad(raw_json.encode('ascii'), AES.block_size))

  encrypted_cipher = PKCS1_OAEP.new(node_key).encrypt(aes_key + aes_iv + hmac_key)

  return {
    'result': 'OK',
    'encrypted-chipher': base64.b64encode(encrypted_cipher).decode('ascii'),
    'encrypted-config-hmac': base64.b64encode(HMAC.new(key=hmac_key, msg=encrypted_config, digestmod=SHA256).digest()).decode('ascii'),
    'encrypted-config': base64.b64encode(encrypted_config).decode('ascii'),
  }

@app.route('/registry/node-state/<path:node_mac_filename>', methods=['PUT'])
def put_node_state(node_mac_filename):
  node_config_path = os.path.join(app.config['root'], 'node-config', node_mac_filename)
  node_state_path = os.path.join(app.config['root'], 'node-state', node_mac_filename)
  if os.path.exists(node_config_path) and os.path.exists(node_state_path):
    # If the node-config exists and the node-state has not been deleted
    # only trust the already submitted node-key
    with open(node_state_path, 'r') as h:
      node_key_pem = json.loads(h.read())['node-key']

  try:
    node_state = json.loads(flask.request.get_data())
    sig = node_state['signature']
    del node_state['signature']
    to_sign = SHA256.new(json.dumps(node_state, sort_keys=True, separators=(',', ':')).encode('ascii'))
    if node_key_pem is None:
      node_key_pem = node_state['node-key']
    node_key = RSA.import_key(node_key_pem)
    pkcs1_15.new(node_key).verify(to_sign, base64.b64decode(sig))
  except Exception as e:
    flask.abort(400)

  with open(node_state_path, 'w') as h:
    try:
      h.write(json.dumps(node_state, indent=2))
    except Exception as e:
      log.error(e)
      flask.abort(500)

  return {'result': 'OK'}

def gunicorn(root, enable_images=False):
  app.config['root'] = root
  app.config['enable_images'] = enable_images
  return app

if __name__ == '__main__':
  app.config['root'] = sys.argv[1]
  app.run()
