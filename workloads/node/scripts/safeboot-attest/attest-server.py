#!/usr/bin/python3
# Source: https://github.com/osresearch/safeboot-attest

"""
Quote validating Attestation Server.

This is a python flask server implementing a single API end-point on /, which
expects a POST request encoded in conventional form (multipart/form-data) that
includes a fields for the `quote` over the `pcr` values, the `sig` on the
quote by the `ak.pub` along with the one-time `nonce` value.

To use from 'curl', you would;
  curl -X -POST -F quote=@"quote.bin" ... <URL>

The API validates that the Quote is signed by the AK with the provided nonce over the provided PCR values.

It then invokes an external handler to verify that the eventlog
meets the policy requirements, and will return any output from this
handler to the attesting machine.

"""
import flask
from flask import request, abort, send_file
import subprocess
import os, sys
from stat import *
import tempfile
import logging
import yaml
import hashlib
import time
from Crypto.Hash import SHA256, HMAC
from Crypto.Cipher import AES
from Crypto.PublicKey import RSA
from Crypto.Random import get_random_bytes
from Crypto.Util.Padding import pad


stderr = logging.StreamHandler(sys.stderr)
log = logging.getLogger(__name__)
log.setLevel(level=logging.INFO)
log.addHandler(stderr)

attest_verify_script = os.environ.get('ATTEST_VERIFY')
if not attest_verify_script:
  attest_verify_script = './attest-verify'

ak_type = 'fixedtpm|stclear|fixedparent|sensitivedataorigin|userwithauth|restricted|sign'

app = flask.Flask(__name__)
app.config['DEBUG'] = True

@app.route('/', methods=['GET'])
def home_get():
  abort(405)

@app.route('/', methods=['POST'])
def home_post():
  _tmp = None
  try:
    # at a minimum there must be:
    required = ('quote', 'sig', 'pcr', 'nonce', 'ak.pub', 'ek.pem')

    for f in required:
      if f not in request.files:
        log.error(f'{f} not present in form data')
        abort(403)

    # Create a temporary directory for the quote file, and make it world
    # readable+executable. (This gets garbage collected after we're done, as do
    # any files we put in there.) We may priv-sep the python API from the
    # underlying safeboot routines at some point, by running the latter behind
    # sudo as another user, so this ensures it would be able to read the quote
    # file.
    _tmp = tempfile.TemporaryDirectory()
    tmpdir = _tmp.name
    s = os.stat(tmpdir)
    os.chmod(tmpdir, s.st_mode | S_IROTH | S_IXOTH)

    # store the required files in variables, as well as into the directory
    files = {}
    for f in required:
      files[f] = request.files[f].read()
      with open(os.path.join(tmpdir, f), 'wb') as fd:
        fd.write(files[f])

    ek_hash = SHA256.new(RSA.import_key(files['ek.pem']).export_key(format='DER')).hexdigest()
    ek_short = ek_hash[0:8]

    # check that the AK meets our requirements
    sub = subprocess.run([
      'tpm2', 'print', '--type', 'TPMT_PUBLIC', os.path.join(tmpdir, 'ak.pub')
    ], stdout=subprocess.PIPE, stderr=sys.stderr)
    if sub.returncode != 0:
      log.error(f'{ek_short}: unable to parse AK')
      abort(403, 'BAD_AK')

    # The output contains YAML description of the attestation key
    ak = yaml.safe_load(sub.stdout)
    if not 'attributes' in ak and not 'value' in ak['attributes']:
      log.error(f'{ek_short}: unable to parse AK')
      abort(403, 'BAD_AK')

    if ak['attributes']['value'] != ak_type:
      log.error(f"{ek_short} bad AK type: {ak['attributes']['value']}")
      abort(403, 'BAD_AK')

    # use the tpm2 checkquote to validate the signature on the quote,
    # the PCRs in the quote, and the one time nonce used for liveliness
    max_drift = 5
    drift = round(int(f'0x{files["nonce"].decode("ascii")}', 16) - time.time())
    if abs(drift) > max_drift:
      # Allow a time drift of {max_drift} seconds
      log.error(f'{ek_short}: Detected nonce timedrift of {drift}s between client and server (max is {max_drift}s)')
      abort (403, 'BAD_QUOTE')

    sub = subprocess.run(['tpm2', 'checkquote',
        '--qualification', files['nonce'],
        '--message', os.path.join(tmpdir, 'quote'),
        '--signature', os.path.join(tmpdir, 'sig'),
        '--pcr', os.path.join(tmpdir, 'pcr'),
        '--public', os.path.join(tmpdir, 'ak.pub'),
      ],
      stdout=subprocess.PIPE,
      stderr=sys.stderr,
    )

    if sub.returncode != 0:
      abort (403, 'BAD_QUOTE')

    # The output contains YAML formatted list of PCRs, but as hexadecimals, which completely messes with `yq`
    # So load it first, quote the values, and then write it to quote.yaml
    quote = yaml.safe_load(sub.stdout)
    quoted_quote = {'pcrs': {}}
    for alg, vals in quote['pcrs'].items():
      quoted_quote['pcrs'][alg] = {}
      for pcr, sha in vals.items():
        quoted_quote['pcrs'][alg][pcr] = f'{sha:x}'

    decoded_quote = os.path.join(tmpdir, 'quote.yaml')
    with open(decoded_quote, 'w') as fd:
      fd.write(yaml.dump(quoted_quote))

    # now ask the verifier to process the quote and decide
    # if the quote meets policy for this ekhash.
    # This is where the actual business logic happens; the other
    # steps have purely been validating that the quote is well formed, etc.
    log.verbose(f'{ek_short}: Verifying quote')
    sub = subprocess.run([attest_verify_script, ek_hash, tmpdir], stdout=subprocess.PIPE, stderr=sys.stderr)

    if sub.returncode != 0:
      log.error(f'{ek_short}: Quote verification failed')
      abort(403, 'verify failed')

    # read the (binary) response from the sub process stdout
    secret_payload = sub.stdout

    log.debug(f'{ek_short}: Sealing response of {len(secret_payload)} bytes')
    # create an ephemeral session key, IV and HMAC key
    aes_key = get_random_bytes(32)
    aes_iv = get_random_bytes(16)
    # andsens: On my Windows Hyper-V machine
    # the max length for a session key file is
    # 48 bytes for some reason, meaning there's
    # not enough space to also include an hmac.
    # To fix this, we reuse the AES IV.
    # What could possibly go wrong?
    # This is pretty close to "rolling your own crypto"
    # territory, but it's 00:21 on a monday and I'm
    # kind of done with these TPM2 shenanigans
    hmac_key = aes_iv
    # hmac_key = get_random_bytes(16)

    # create the session key file that concatenates the
    # AES key, IV and hmac key. 64-bytes is the maximum
    # allowed with tpm2
    secret_filename = os.path.join(tmpdir, 'secret.bin')
    with open(secret_filename, 'wb') as f:
      f.write(aes_key + aes_iv)
      # f.write(aes_key + aes_iv + hmac_key)

    # and now seal it with the AK/EK into a credential blob
    sealed_filename = os.path.join(tmpdir, 'credential.blob')
    sub = subprocess.run([
      'tpm2', 'makecredential',
      '--quiet',
      '--tcti', 'none',
      '--secret', secret_filename,
      '--public', os.path.join(tmpdir, 'ek.pem'),
      '--key-algorithm', 'rsa',
      '--name', f'000b{SHA256.new(files["ak.pub"]).hexdigest()}',
      '--credential-blob', sealed_filename,
      ],
      stdout=subprocess.PIPE,
      stderr=sys.stderr,
    )

    if sub.returncode != 0:
      log.error(f'{ek_short}: makecredential failed')
      abort(500, "sealing failed")

    # use the AES key and IV to encrypt the secret data
    enc = AES.new(aes_key, AES.MODE_CBC, iv=aes_iv)
    cipher = enc.encrypt(pad(secret_payload, AES.block_size))

    # compute the HMAC on the encrypted secret data
    hmac = HMAC.new(key=hmac_key, msg=cipher, digestmod=SHA256).digest()

    # append the hmac and cipher text to the cred file
    with open(sealed_filename, 'ab') as f:
      f.write(hmac)
      f.write(cipher)

    return send_file(sealed_filename)
  except Exception as e:
    log.error(f'{ek_short}: {e}')
    abort(500, 'unknown error, check server logs for more information')
  finally:
    if _tmp is not None:
      _tmp.cleanup()

if __name__ == '__main__':
  app.run()
