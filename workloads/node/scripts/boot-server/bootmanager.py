import logging
from pathlib import Path
from .context import Context, BootPath
from . import AnyIPAddress, NodeState
import macaddress
from typing import overload
from .node import Node

log = logging.getLogger(__name__)

def get_boot_spec(context: Context, match_string: str) -> BootPath:
  return next((
    boot_spec for matcher, boot_spec in reversed(context['boot_map'].items())
    if matcher.search(match_string) is not None
  ), None)

@overload
def get_image_dir(context: Context, ipaddr: AnyIPAddress, variant: str) -> Path:
  node = Node.get_by_ip(context, ipaddr)
  if node is None:
    log.warning(f'Failed to map IP address {ipaddr} to a known machine-id')
    return Path(variant)
  else:
    return get_image_dir(node)

@overload
def get_image_dir(context: Context, mac: macaddress.MAC, variant: str) -> Path:
  node = Node.get_by_mac(context, mac)
  if node is None:
    log.warning(f'Failed to map MAC address {mac} to a known machine-id')
    return Path(variant)
  else:
    return get_image_dir(context, node)

def get_image_dir(context: Context, node: Node, variant: str) -> Path:
  # get image node is set to
  return Path(variant)


def image_upload_completed(context: Context, variant: str):
  pass

def pxe_request_received(context: Context, macaddr, boot_spec, image_dir):
  pass

def tftp_download_initiated(context: Context, boot_spec, filename):
  pass

def node_state_reported(context: Context, node: Node, state: NodeState):
  pass

# if
# * no node in variant is testing
# * there is an image to test
# * node is not control plan
# then -> set node to test image
# else -> serve current image
