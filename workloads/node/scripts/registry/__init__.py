#!/usr/bin/python3

import flask
import os
import sys
import re
import logging
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

@app.route('/node-state/<mac>.json', methods=['PUT'])
def put_node_state(mac):
  if re.match(r'^([0-9a-f]{2}-){5}[0-9a-f]{2}$', mac) is None:
    flask.abort(400)
  with open(os.path.join(app.config['root'], f'node-state/{mac}.json'), 'w') as h:
    h.write(flask.request.get_data().decode())
  return {'result': 'OK'}

@app.route('/attest', methods=['POST'])
def post_attest():
  verify_attestation(flask.request.files)

def gunicorn(root):
  app.config['root'] = root
  return app

if __name__ == '__main__':
  app.config['root'] = sys.argv[1]
  app.run()
