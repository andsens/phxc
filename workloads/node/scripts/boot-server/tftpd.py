import asyncio, functools, logging, os, re
import uuid
import py3tftp.protocols
import py3tftp.exceptions
import py3tftp.file_io
import py3tftp.netascii
import ipaddress
import py3tftp.tftp_packet
from . import Context
from .boot_events import tftp_download_initiated
from .node import Node
from typing import Pattern, TypedDict, cast

log = logging.getLogger(__name__)

class BootPath(TypedDict):
  variant: str
  filename: str

boot_spec_map: dict[Pattern, BootPath] = {
  re.compile(r'^boot.img$'): {
    'variant': 'rpi5',
    'filename': 'boot.img'
  },
  re.compile(r'^config.txt$'): {
    'variant': 'rpi5',
    'filename': 'config.txt'
  },
}

async def tftpd(ctx: Context, ready_event: asyncio.Event):
  log.info('Starting TFTP server')

  def get_file_reader(mode, ipaddr, filename, opts):
    log.debug(f'get {filename.decode()}')
    rel_filename = os.fsdecode(filename).lstrip('./')
    try:
      node = Node(ctx, uuid.UUID(rel_filename))
    except ValueError:
      node = Node.get_by_ip(ctx, ipaddr)
      if node is None:
        raise Exception(f'Unable to find node with the IP {ipaddr}')
    image = node.booting_image
    if image is None:
      raise Exception(f'The node {node} does not have a boot image configured')
    # Check to see if the file has a special mapping, last match wins
    boot_spec = next((p for r, p in reversed(boot_spec_map.items()) if r.match(rel_filename)), None)
    if boot_spec is not None:
      if boot_spec['filename'] not in image.files:
        raise Exception(f'The node {node} requested an unknown file named "{rel_filename}"')
      abspath = image.abspath / boot_spec['filename']
    else:
      abspath = image.boot_file.abspath

    tftp_download_initiated(ctx, node, abspath.name)
    # Verify that the formed path is under the images directory.
    try:
      abspath.relative_to(ctx.images)
    except ValueError:
      raise FileNotFoundError
    # Verify that we are not accessing a reserved file.
    if abspath.is_reserved():
      raise FileNotFoundError
    return FileReader(abspath, opts, mode)

  loop = asyncio.get_running_loop()
  transport, protocol = await loop.create_datagram_endpoint(
    lambda: TFTPServerProtocol(ctx, get_file_reader, loop, {}),
    local_addr=(str(ctx.host_ip), 69,))
  ready_event.set()
  await ctx.shutdown_event.wait()
  log.info('Closing TFTP server')
  transport.close()

class TFTPServerProtocol(py3tftp.protocols.BaseTFTPServerProtocol):

  def __init__(self, ctx: Context, get_file_reader, loop, extra_opts):
    self.get_file_reader = get_file_reader
    super().__init__(str(ctx.host_ip), loop, extra_opts)

  def datagram_received(self, data: bytes, addr):
    """
    Opens a read or write connection to remote host by scheduling
    an asyncio.Protocol.
    """
    log.debug('received: {}'.format(data.decode()))

    first_packet = self.packet_factory.from_bytes(data)
    if(first_packet is None):
      raise py3tftp.exceptions.BadRequest('First packet ')
    log.debug('packet type: {}'.format(first_packet.pkt_type))
    if first_packet.is_wrq():
      raise py3tftp.exceptions.BadRequest('Uploads are not allowed')
    elif not first_packet.is_rrq():
      raise py3tftp.protocols.ProtocolException('Received incompatible request, ignoring.')

    (ipaddr, port) = addr
    file_handler_cls = functools.partial(self.get_file_reader, cast(py3tftp.tftp_packet.TFTPRequestPacket, first_packet).mode, ipaddress.ip_address(ipaddr))
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
    self._f = self._open_file()
    self.fname = fname
    self.chunk_size = chunk_size
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
