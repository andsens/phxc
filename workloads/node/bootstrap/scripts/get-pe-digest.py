from collections import OrderedDict
import json
import hashlib
import sys
from binascii import hexlify

import docopt
from signify.authenticode import SignedPEFile

__doc__ = '''get-pe-digest.py - Extract the digest used for signing a PE File
Usage:
  get-pe-digest.py [-j|-b] [-a ALGO...] PEFILE

Options:
  -b --batch      Output without algorithm descriptor
  -j --json       Output in JSON format
  -a --algo ALGO  Generate hash with ALGO [default: sha1 sha256 sha384]
                  https://docs.python.org/3/library/hashlib.html#constructors
'''

if __name__ == '__main__':
  params = docopt.docopt(__doc__)
  try:
    with open(params['PEFILE'], 'rb') as f:
      fp = SignedPEFile(f).get_fingerprinter()
      fp.add_authenticode_hashers(*map(lambda h: getattr(hashlib, h), params['--algo']))
      digests_binary = fp.hash()
      digests = OrderedDict()
      for algo in params['--algo']:
        digest = hexlify(digests_binary[algo]).decode('ascii')
        if params['--json']:
          digests[algo] = digest
        else:
          if params['--batch']:
            print(digest)
          else:
            print(f'{algo}: {digest}')
      if params['--json']:
        print(json.dumps(digests, indent=(2 if sys.stdout.isatty() else None)))
  except Exception as e:
    sys.stderr.write(f'{e}\n')
    sys.exit(1)
