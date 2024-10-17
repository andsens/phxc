import asyncio, logging, os, re
from pathlib import Path
import py3tftp.protocols
import py3tftp.exceptions
import py3tftp.file_io
import py3tftp.netascii

log = logging.getLogger(__name__)

async def tftpd(ready_event, shutdown_event, host_ip, root: Path):
  log.info('Starting TFTP server')

  loop = asyncio.get_running_loop()
  transport, protocol = await loop.create_datagram_endpoint(
    lambda: TFTPServerProtocol(root, host_ip, loop, {}),
    local_addr=(host_ip, 69,))
  ready_event.set()
  await shutdown_event.wait()
  log.info('Closing TFTP server')
  transport.close()

filemap = {
  re.compile(r'^boot.img$'): Path('rpi5/boot.img'),
  re.compile(r'^config.txt$'): Path('rpi5/config.txt'),
}

def map_file(root: Path, fname: bytes):
  rel_filename = os.fsdecode(fname).lstrip('./')
  # Last match wins
  abs_path = root / next((p for r, p in reversed(filemap.items()) if r.match(rel_filename)), rel_filename)
  # Verify that the formed path is under the root directory.
  try:
    abs_path.relative_to(root)
  except ValueError:
    raise FileNotFoundError
  # Verify that we are not accessing a reserved file.
  if abs_path.is_reserved():
    raise FileNotFoundError
  return abs_path

class TFTPServerProtocol(py3tftp.protocols.BaseTFTPServerProtocol):

  def __init__(self, root: Path, host_interface, loop, extra_opts):
    self.root = root
    super().__init__(host_interface, loop, extra_opts)

  def select_protocol(self, packet):
    log.debug('packet type: {}'.format(packet.pkt_type))
    if packet.is_rrq():
      return py3tftp.protocols.RRQProtocol
    elif packet.is_wrq():
      raise py3tftp.exceptions.BadRequest('Uploads are not allowed')
    else:
      raise py3tftp.protocols.ProtocolException('Received incompatible request, ignoring.')

  def select_file_handler(self, packet):
    if packet.is_rrq():
      return lambda filename, opts: FileReader(self.root, filename, opts, packet.mode)
    else:
      raise py3tftp.exceptions.BadRequest('Uploads are not allowed')


class FileReader(object):
  """
  A wrapper around a regular file that implements:
  - read_chunk - for closing the file when bytes read is
    less than chunk_size.
  - finished - for easier notifications
  interfaces.
  When it goes out of scope, it ensures the file is closed.
  """

  def __init__(self, root: Path, fname, chunk_size=0, mode=None):
    self._f = None
    log.info(f'get {fname.decode()}')
    self.fname = map_file(root, fname)
    self.chunk_size = chunk_size
    self._f = self._open_file()
    self.finished = False

    if mode == b'netascii':
      self._f = py3tftp.netascii.Netascii(self._f)

  def _open_file(self):
    return self.fname.open('rb')

  def file_size(self):
    return self.fname.stat().st_size

  def read_chunk(self, size=None):
    size = size or self.chunk_size
    if self.finished:
      return b''

    data = self._f.read(size)

    if not data or (size > 0 and len(data) < size):
      self._f.close()
      self.finished = True

    return data

  def __del__(self):
    if self._f and not self._f.closed:
      self._f.close()
