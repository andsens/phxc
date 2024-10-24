import json, logging, uuid
from pathlib import Path
import etcd, macaddress
from . import AnyIPAddress
from .inmemorykvstore import InMemoryKVStore
from .bootmanager import BootManager
from .node import Node
from typing import overload

log = logging.getLogger(__name__)

class Registry(object):

  client: etcd.Client | InMemoryKVStore
  ip_to_mac_ttl = 3600

  def __init__(self, kv_client: etcd.Client | InMemoryKVStore):
    self.client = kv_client
    self.bootmgr = BootManager(self)

  async def run(self, ready_event, shutdown_event):
    log.info('Starting boot manager')
    ready_event.set()
    await shutdown_event.wait()

  def __get(self, key: str):
    try:
      return self.client.read(f'/boot-server/{key}').value
    except (etcd.EtcdKeyNotFound, KeyError):
      return None

  def __set(self, key: str, val: str, ttl: int | None = None):
    self.client.write(f'/boot-server/{key}', val, ttl=ttl)

  def ip_requested(self, mac: macaddress.MAC, ip: AnyIPAddress):
    self.__set(f'ip-to-mac/{ip}', mac, self.ip_to_mac_ttl)
    self.__set(f'mac-to-ip/{mac}', ip, self.ip_to_mac_ttl)

  def get_node_by_mac(self, mac: macaddress.MAC) -> Node | None:
    machine_id = self.__get(f'mac-to-machine-id/{mac}')
    return Node(self.client, machine_id) if machine_id is not None else None

  def get_node_by_ip(self, ip: AnyIPAddress) -> Node | None:
    mac = self.__get(f'ip-to-mac/{ip}')
    return self.get_node_by_mac(mac) if mac is not None else None

  def get_all_nodes(self) -> list[Node]:
    prefix = '/boot-server/nodes/states/'
    try:
      return map(lambda n: Node(n.key[len(prefix):]), self.client.read(prefix, recursive=True).children)
    except (etcd.EtcdKeyNotFound, KeyError):
      return []

  def import_host_info(self, import_path: Path):
    log.info('Updating state, config, and authn-key of host node')
    host_machine_id = uuid.UUID((import_path / 'machine-id').read_text())
    self.update_node_state(host_machine_id, json.loads((import_path / 'node-state.json').read_text()))
    self.update_node_config(host_machine_id, json.loads((import_path / 'node-config.json').read_text()))
    self.update_node_authn_key(host_machine_id, json.loads((import_path / 'authn-key.json').read_text()))

  @overload
  def get_variant_dir(self, ipaddr: AnyIPAddress, variant) -> Path:
    node = self.get_node_by_ip(ipaddr)
    if node is None:
      log.warning(f'Failed to map IP address {ipaddr} to a known machine-id')
      return Path(variant)
    else:
      return self.get_variant_dir(node)

  @overload
  def get_variant_dir(self, mac: macaddress.MAC, variant) -> Path:
    node = self.get_node_by_mac(mac)
    if node is None:
      log.warning(f'Failed to map MAC address {mac} to a known machine-id')
      return Path(variant)
    else:
      return self.get_variant_dir(node)

  def get_variant_dir(self, node: Node, variant) -> Path:
    # get image node is set to
    return Path(variant)
