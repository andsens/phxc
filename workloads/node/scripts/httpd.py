'''httpd.py
Usage:
  httpd.py [options] [(-b BUNDLE -k KEY)] HOST_IP PATH

Options:
  -p --port PORT        The port to listen on [default: 8020]
  -b --tls-bundle PATH  Path to the TLS bundle to use
  -k --tls-key PATH     Path to the private key for the serving certificate
'''

import docopt
import http.server
import ssl
import logging
import sys
import os
import functools

log = logging.getLogger('httpd.py')
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler(sys.stderr)
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

params = docopt.docopt(__doc__)

httpd = http.server.HTTPServer(
  (params['HOST_IP'], int(params['--port'])),
  functools.partial(
    http.server.SimpleHTTPRequestHandler,
    directory=params['PATH']
  )
)

if params['--tls-bundle'] is not None:
  context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
  context.load_cert_chain(params['--tls-bundle'], params['--tls-key'])
  httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

log.debug(f'Webserver started')
httpd.serve_forever()
