import ipaddress
from typing import TypedDict, Literal, Union
from werkzeug.exceptions import Forbidden

AnyIPAddress = ipaddress.IPv4Address | ipaddress.IPv6Address

class ErrorMessage(Exception):
  pass

class JWTVerificationError(Forbidden):
  pass

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
  'filesystem': None | str,
  'partitions': None | PartitionsState
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
  'authn': None | AuthnKey,
  'random-secret': None | RandomSecretKey,
  'disk-encryption': None | DiskEncryptionKey,
  'rpi-otp': None | RPiOTPKey,
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
  'force': bool,
})

NetworkConfig = Union[TypedDict('NetworkConfig', {
  'mac': str,
  'dhcp': Literal[True]
}), TypedDict('Attributes', {
  'mac': str,
  'dhcp': Literal[False],
  'static': list[str],
})]

NodeConfig = TypedDict('NodeConfig', {
  'disk': DiskConfig,
  'hostname': str,
  'node-label': list[str],
  'networks': dict[str, NetworkConfig],
})
