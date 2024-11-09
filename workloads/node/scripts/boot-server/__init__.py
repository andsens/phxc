import ipaddress
import re
from typing import Any, NotRequired, Optional, TypedDict, Literal, Union, Never
import asyncio
from pathlib import Path
from typing import TypedDict
import etcd
import urllib.parse
import yaml
AnyIPAddress = ipaddress.IPv4Address | ipaddress.IPv6Address

class ErrorMessage(Exception):
  pass

VariantMap = dict[re.Pattern[Any], str]

class EtcdResult:
  key: str
  value: str
  expiration: int
  ttl: int
  modifiedIndex: int
  createdIndex: int
  newKey: bool
  dir: bool

class Context(object):
  dbprefix: str = '/boot-server'
  ip_to_mac_ttl: int = 60 * 60
  tentative_authn_key_ttl: int = 60 * 60 * 24
  host_ip: ipaddress.IPv4Address
  images: Path
  admin_pubkey: str
  sb_pubkey: str
  import_path: Path
  variant_map: VariantMap
  db: etcd.Client

  def __init__(self, host_ip: ipaddress.IPv4Address, etcd_url: str, shutdown_event: asyncio.Event):
    root = Path('/data')
    self.images = root / 'images'
    self.admin_pubkey = (root / 'admin.pem').read_text()
    self.sb_pubkey = (root / 'sb.pem').read_text()
    self.import_path = root / 'host'
    self.variant_map = dict(
      (re.compile(regex), variant)
      for regex, variant in yaml.safe_load((root / 'variant-map.yaml').read_text()).items()
    )
    etcd_parts = urllib.parse.urlparse(etcd_url)
    self.db = etcd.Client(protocol=etcd_parts.scheme, host=getattr(etcd_parts, 'hostname'), port=getattr(etcd_parts, 'port'), allow_reconnect=True)
    self.host_ip = host_ip
    self.shutdown_event = shutdown_event


Partition = TypedDict('Partition', {
  'node': str,
  'start': int,
  'size': int,
  'type': str,
  'uuid': str,
})

PartitionsState = TypedDict('PartitionsState', {
  'label': str,
  'id': str,
  'device': str,
  'unit': str,
  'firstlba': int,
  'lastlba': int,
  'sectorsize': int,
  'partitions': list[Partition]
})

BlockDevice = TypedDict('BlockDevice', {
  'devpath': str,
  'filesystem': str,
  'partitions': PartitionsState
})

AuthnKey = TypedDict('AuthnKey', {
  'persisted': bool,
})

RandomSecretKey = TypedDict('RandomSecretKey', {
  'source': Literal['generated'] | Literal['rpi-otp'],
})

DiskEncryptionKey = TypedDict('DiskEncryptionKey', {
  'persisted': bool,
})

RPiOTPKey = TypedDict('RPiOTPKey', {
  'initialized': bool,
})

Keys = TypedDict('Keys', {
  'authn': NotRequired[AuthnKey],
  'random-secret': NotRequired[RandomSecretKey],
  'disk-encryption': NotRequired[DiskEncryptionKey],
  'rpi-otp': NotRequired[RPiOTPKey],
})

Nic = TypedDict('Nic', {
  'ifname': str,
  'mac': str,
})

RootImg = TypedDict('RootImg', {
  'src': Literal['boot-server'] | str,
  'sha256': str,
})

NodeState = TypedDict('NodeState', {
  'report-phase': Literal['initial'] | Literal['final'],
  'variant': str,
  'rootimg': RootImg,
  'primary-mac': str,
  'boot-server': str,
  'keys': Keys,
  'hostname': str,
  'nics': list[Nic],
  'blockdevices': list[BlockDevice]
})

DiskConfig = TypedDict('DiskConfig', {
  'encryption-key': str,
  'devpath': str,
  'force': NotRequired[bool],
})

NetworkConfig = TypedDict('NetworkConfig', {
  'mac': str,
  'dhcp': bool,
  'static': list[str],
})

NodeConfig = TypedDict('NodeConfig', {
  'disk': DiskConfig,
  'hostname': str,
  'node-label': list[str],
  'networks': dict[str, NetworkConfig],
})

AuthentihashSet = TypedDict('AuthentihashSet', {
  'sha1': str,
  'sha256': str,
  'sha384': str
})

BuildMeta = TypedDict('BuildMeta', {
  'variant': str,
  'boot-file': str,
  'build-date': str,
  'sha256sums': dict[str, str],
  'authentihashes': dict[str, AuthentihashSet] | dict[Never, Never]
})

ImageState = Literal['untested'] | Literal['stable'] | Literal['oldstable'] | Literal['crashed']

ImageInfo = TypedDict('ImageInfo', {
  'upload-date': str,
  'state': ImageState,
  'build': BuildMeta
})
