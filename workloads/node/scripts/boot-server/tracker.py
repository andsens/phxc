import ipaddress, logging, time, uuid
from pathlib import Path
from typing import overload
import macaddress

log = logging.getLogger(__name__)

AnyIPAddress = ipaddress.IPv4Address | ipaddress.IPv6Address

ip_to_mac_ttl = 3600

class BootTracker(object):

  ip_to_mac_map: dict[AnyIPAddress, (macaddress.MAC, int)]

  def __init__(self):
    self.ip_to_mac_map = {}

  def ip_requested(self, mac: macaddress.MAC, ip: AnyIPAddress):
    now = time.time()
    self.ip_to_mac_map[ip] = (mac, now)
    self.ip_to_mac_map = { ip: (mac, t) for ip, (mac, t) in self.ip_to_mac_map.items() if now - t < ip_to_mac_ttl }

  def node_state_reported(self, machine_id):
    pass

  @overload
  def get_variant_dir(self, ipaddr: AnyIPAddress, variant) -> Path:
    if ipaddr in self.ip_to_mac_map:
      (macaddr, ttl) = self.ip_to_mac_map[ipaddr]
      return self.get_variant_dir(macaddr, variant)
    else:
      log.warning(f'Failed to map IP address {ipaddr} to a known MAC address')
      return Path(variant)

  @overload
  def get_variant_dir(self, macaddr: macaddress.MAC, variant) -> Path:
    return Path(variant)

  def get_variant_dir(self, machine_id: uuid.UUID, variant) -> Path:
    return Path(variant)
