import asyncio, socket, logging, re
from pathlib import Path
import ipaddress, yaml, dhcppython
from .registry import Registry
from . import AnyIPAddress
from typing import TypedDict, Pattern, Any
import macaddress

log = logging.getLogger(__name__)

BootSpec = TypedDict('BootSpec', {
  'variant': str,
  'filename': str
})

BootMap = dict[Pattern[Any], BootSpec | None]

async def dhcp_proxy(ready_event: asyncio.Event, shutdown_event: asyncio.Event, registry: Registry,
                     boot_map: Path, host_ip: AnyIPAddress):
  log.info('Starting DHCP proxy')
  proxy_ip = host_ip
  tftpd_ip = host_ip

  compiled_boot_map = dict((re.compile(regex), boot_spec) for regex, boot_spec in yaml.safe_load(boot_map.read_text()).items())

  DSCP_TOS_ROUTING_CONTROL = 0xc0
  IP_PMTUDISC_DONT = 0
  IP_MTU_DISCOVER = 10
  sock_67 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
  sock_67.setsockopt(socket.IPPROTO_IP, IP_MTU_DISCOVER, IP_PMTUDISC_DONT) # Remove the DF (Don't fragment) flag
  sock_67.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, DSCP_TOS_ROUTING_CONTROL)
  sock_67.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  sock_67.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
  sock_67.bind(('', 67 ))
  sock_4011 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
  sock_4011.setsockopt(socket.IPPROTO_IP, IP_MTU_DISCOVER, IP_PMTUDISC_DONT) # Remove the DF (Don't fragment) flag
  sock_4011.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, DSCP_TOS_ROUTING_CONTROL)
  sock_4011.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  sock_4011.bind(('', 4011 ))

  base_option_list = [
    dhcppython.options.ServerIdentifier(code=54, length=len(proxy_ip.packed), data=proxy_ip.packed),
    dhcppython.options.VendorClassIdentifier(code=60, length=len('PXEClient'.encode()), data='PXEClient'.encode()),
    dhcppython.options.TFTPServerName(code=66, length=len(str(tftpd_ip).encode()), data=str(tftpd_ip).encode())
  ]

  loop = asyncio.get_running_loop()
  transport_67, protocol = await loop.create_datagram_endpoint(
    lambda: DHCPProxy(registry, 67, proxy_ip, tftpd_ip, base_option_list, compiled_boot_map),
    sock=sock_67
  )
  transport_4011, protocol = await loop.create_datagram_endpoint(
    lambda: DHCPProxy(registry, 4011, proxy_ip, tftpd_ip, base_option_list, compiled_boot_map),
    sock=sock_4011
  )
  ready_event.set()
  await shutdown_event.wait()
  log.info('Closing DHCP proxy')
  transport_67.close()
  transport_4011.close()

class DHCPProxy(object):

  registry: Registry
  port: int
  proxy_ip: AnyIPAddress
  tftpd_ip: AnyIPAddress
  base_option_list: list[dhcppython.options.Option]
  boot_map: BootMap

  def __init__(self, registry: Registry, port: int,
               proxy_ip: AnyIPAddress, tftpd_ip: AnyIPAddress,
               base_option_list: list[dhcppython.options.Option], boot_map: BootMap):
    self.registry = registry
    self.port = port
    self.proxy_ip = proxy_ip
    self.tftpd_ip = tftpd_ip
    self.base_option_list = base_option_list
    self.boot_map = boot_map

  def connection_made(self, transport):
    self.transport = transport

  def connection_lost(self, exc):
    if exc is not None:
      log.exception(exc)

  def datagram_received(self, raw_message, addr):
    try:
      (client_ip, client_port) = addr
      message = dhcppython.packet.DHCPPacket.from_bytes(raw_message)
      log.debug(f'Received message: {message}')

      def get_opt(code: int, default=None):
        opt = message.options.by_code(code)
        return opt.value[opt.key] if opt is not None else default

      macaddr: macaddress.MAC = macaddress.parse(message.chaddr, macaddress.MAC)
      vendor_class_identifier = get_opt(dhcppython.options.VendorClassIdentifier.code, '')
      if 'PXEClient' not in vendor_class_identifier:
        log.debug(f'Non-PXE client request received from {macaddr}')
        return

      dhcp_message_type = get_opt(dhcppython.options.MessageType.code)
      if dhcp_message_type == 'DHCPDISCOVER' and self.port == 67:
        response_type = dhcppython.packet.DHCPPacket.Offer
      elif dhcp_message_type == 'DHCPREQUEST' and self.port == 67:
        requested_ip = get_opt(dhcppython.options.RequestedIPAddress.code)
        if requested_ip is not None:
          log.debug(f'{macaddr} requested IP {requested_ip}')
          self.registry.ip_requested(macaddr, ipaddress.ip_address(requested_ip))
        return
      elif dhcp_message_type == 'DHCPREQUEST' and self.port == 4011:
        response_type = dhcppython.packet.DHCPPacket.Ack
      else:
        log.info(f'Unhandled DHCP message type {dhcp_message_type} from {macaddr} on port {self.port}')
        return

      log.info(f'PXE client {dhcp_message_type} received from {macaddr}')
      option_list = list(self.base_option_list)
      uuid_opt = message.options.by_code(97)
      if uuid_opt is not None:
        option_list.append(uuid_opt)

      client_system = get_opt(93, '')
      match_string = f'{vendor_class_identifier}/{client_system}'
      file_path = None
      for matcher, boot_spec in self.boot_map.items():
        if matcher.search(match_string) is not None:
          if boot_spec is not None:
            # No break, last match wins
            file_path = str(self.registry.get_variant_dir(macaddr, boot_spec['variant']) / boot_spec['filename']).encode()
          else:
            file_path = ''.encode()

      if file_path is None:
        log.info(f"No match found in boot-map for '{match_string}'")
        return
      option_list.append(dhcppython.options.BootfileName(code=67, length=len(file_path), data=file_path))

      response = response_type(
        message.chaddr,
        seconds=0,
        tx_id=message.xid,
        yiaddr='0.0.0.0',
        sname=str(self.tftpd_ip).encode(),
        fname=file_path,
        option_list=option_list
      )
      response.siaddr = self.proxy_ip
      log.debug(f'Responding with {response}')
      self.transport.sendto(response.asbytes, ('255.255.255.255' if client_ip == '0.0.0.0' else client_ip, client_port))
    except SystemExit as e:
      return
    except Exception as e:
      log.exception(e)
