#!/usr/bin/python3

import flask
import os
import sys
import re
import logging
import json
from registry.verify_attestation import verify_attestation

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

@app.route('/registry/node-config/<path:node_config_path>', methods=['GET'])
def get_node_config(node_config_path):
  with open(os.path.join(app.config['root'], 'node-config', node_config_path), 'r') as h:
    try:
      raw_json = h.read()
      json.loads(raw_json)  # Make sure we are sending back valid JSON
      return raw_json
    except Exception as e:
      log.error(e)
      flask.abort(500)

@app.route('/registry/node-state/<path:node_state_path>', methods=['PUT'])
def put_node_state(node_state_path):
  with open(os.path.join(app.config['root'], 'node-state', node_state_path), 'w') as h:
    try:
      node_state = json.loads(flask.request.get_data())
      h.write(json.dumps(node_state, indent=2))
    except Exception as e:
      log.error(e)
      flask.abort(400)
  return {'result': 'OK'}

@app.route('/registry/attest', methods=['POST'])
def post_attest():
  verify_attestation(flask.request.files)

def gunicorn(root, enable_images=False):
  app.config['root'] = root
  app.config['enable_images'] = enable_images
  return app

if __name__ == '__main__':
  app.config['root'] = sys.argv[1]
  app.run()
