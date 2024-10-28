import logging
from pathlib import Path
from .context import Context, BootSpec
from . import AnyIPAddress
import macaddress
from typing import overload
from .node import Node

log = logging.getLogger(__name__)

def get_boot_spec(context: Context, match_string: str) -> BootSpec:
  return next((
    boot_spec for matcher, boot_spec in reversed(context['boot_map'].items())
    if matcher.search(match_string) is not None
  ), None)

@overload
def get_image_dir(self, ipaddr: AnyIPAddress, variant) -> Path:
  node = self.get_node_by_ip(ipaddr)
  if node is None:
    log.warning(f'Failed to map IP address {ipaddr} to a known machine-id')
    return Path(variant)
  else:
    return self.get_image_dir(node)

@overload
def get_image_dir(self, mac: macaddress.MAC, variant) -> Path:
  node = self.get_node_by_mac(mac)
  if node is None:
    log.warning(f'Failed to map MAC address {mac} to a known machine-id')
    return Path(variant)
  else:
    return self.get_image_dir(node)

def get_image_dir(self, node: Node, variant) -> Path:
  # get image node is set to
  return Path(variant)

# if
# * no node in variant is testing
# * there is an image to test
# * node is not control plan
# then -> set node to test image
# else -> serve current image
