import asyncio, functools, logging, os, re
from pathlib import Path
import py3tftp.protocols
import py3tftp.exceptions
import py3tftp.file_io
import py3tftp.netascii
import ipaddress
from .tracker import BootTracker

log = logging.getLogger(__name__)

boot_spec_map = {
  re.compile(r'^boot.img$'): {
    'variant': 'rpi5',
    'filename': 'boot.img'
  },
  re.compile(r'^config.txt$'): {
    'variant': 'rpi5',
    'filename': 'config.txt'
  },
}

async def tftpd(ready_event, shutdown_event, boot_tracker: BootTracker, host_ip, root: Path):
  log.info('Starting TFTP server')

  def get_file_reader(mode, ipaddr, filename, opts):
    log.info(f'get {filename.decode()}')
    rel_filename = os.fsdecode(filename).lstrip('./')
    # Check to see if the file has a special mapping, last match wins
    boot_spec = next((p for r, p in reversed(boot_spec_map.items()) if r.match(rel_filename)), None)
    abs_path = root / (
      rel_filename if boot_spec is None else \
      boot_tracker.get_variant_dir(ipaddr, boot_spec['variant']) / boot_spec['filename']
    )
    # Verify that the formed path is under the root directory.
    try:
      abs_path.relative_to(root)
    except ValueError:
      raise FileNotFoundError
    # Verify that we are not accessing a reserved file.
    if abs_path.is_reserved():
      raise FileNotFoundError
    return FileReader(abs_path, opts, mode)

  loop = asyncio.get_running_loop()
  transport, protocol = await loop.create_datagram_endpoint(
    lambda: TFTPServerProtocol(get_file_reader, host_ip, loop, {}),
    local_addr=(host_ip, 69,))
  ready_event.set()
  await shutdown_event.wait()
  log.info('Closing TFTP server')
  transport.close()

class TFTPServerProtocol(py3tftp.protocols.BaseTFTPServerProtocol):

  def __init__(self, get_file_reader, host_interface, loop, extra_opts):
    self.get_file_reader = get_file_reader
    super().__init__(host_interface, loop, extra_opts)

  def datagram_received(self, data, addr):
    """
    Opens a read or write connection to remote host by scheduling
    an asyncio.Protocol.
    """
    log.debug('received: {}'.format(data.decode()))

    first_packet = self.packet_factory.from_bytes(data)

    log.debug('packet type: {}'.format(first_packet.pkt_type))
    if first_packet.is_wrq():
      raise py3tftp.exceptions.BadRequest('Uploads are not allowed')
    elif not first_packet.is_rrq():
      raise py3tftp.protocols.ProtocolException('Received incompatible request, ignoring.')

    (ipaddr, port) = addr
    file_handler_cls = functools.partial(self.get_file_reader, first_packet.mode, ipaddress.ip_address(ipaddr))
    connect = self.loop.create_datagram_endpoint(
        lambda: py3tftp.protocols.RRQProtocol(data, file_handler_cls, addr, self.extra_opts),
        local_addr=(self.host_interface, 0, ))
    self.loop.create_task(connect)


class FileReader(object):
  """
  A wrapper around a regular file that implements:
  - read_chunk - for closing the file when bytes read is
    less than chunk_size.
  - finished - for easier notifications
  interfaces.
  When it goes out of scope, it ensures the file is closed.
  """

  def __init__(self, fname, chunk_size=0, mode=None):
    self._f = None
    self.fname = fname
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
