import logging
import uuid
from . import NodeState, Context
from .node import Node
from .image import Image

log = logging.getLogger(__name__)

def image_upload_completed(ctx: Context, image: Image):
  # state = context['db'].get(f'nodes/states/{self.machine_id}')
  # # Schedule for testing
  # loop = asyncio.get_event_loop()
  # loop.create_task(do_something('T' + str(i)))
  log.info(f'An image "{image}" has been uploaded')

def pxe_request_received(ctx: Context, node: Node):
  # Node is starting up
  log.info(f'The node "{node}" has sent a PXE request')

def node_crashed_on_bootup(ctx: Context, node: Node):
  # Node is starting up
  log.info(f'The node "{node}" crashed while booting {node.booting_image}')

def tftp_download_initiated(ctx: Context, node: Node, filename):
  # Node is acting on the PXE response
  log.info(f'The node "{node}" is downloading {filename} via TFTP')

def boot_server_discovery_request_received(ctx: Context, node: Node):
  # Image can start initramfs
  log.info(f'The node "{node}" has sent a boot-server discovery request')

def authn_key_submitted(ctx: Context, node: Node | uuid.UUID):
  # Image can switch root
  log.info(f'The node "{node}" has submitted its authn-key')

def initial_node_state_reported(ctx: Context, node: Node, state: NodeState):
  # Image has passed key setup
  log.info(f'The node "{node}" has submitted its initial state')

def final_node_state_reported(ctx: Context, node: Node, state: NodeState):
  # Image can decrypt disk
  log.info(f'The node "{node}" has submitted its final state')

def kubernetes_node_ready(ctx: Context, node: Node):
  # Image has fully booted
  log.info(f'The node "{node}" has connected to kubernetes and is ready')
