import asyncio, socket, logging, re
from pathlib import Path
import ipaddress, yaml, dhcppython
from .tracker import BootTracker
from typing import TypedDict, Pattern, Any
import macaddress

log = logging.getLogger(__name__)


class BootSpec(TypedDict):
  variant: str
  filename: str

BootMap = dict[Pattern[Any], BootSpec | None]

async def dhcp_proxy(ready_event, shutdown_event, boot_tracker: BootTracker, boot_map: Path, host_ip):
  log.info('Starting DHCP proxy')
  proxy_ip = ipaddress.ip_address(host_ip)
  tftpd_addr = host_ip

  with boot_map.open('r') as h:
    compiled_boot_map = dict((re.compile(regex), boot_spec) for regex, boot_spec in yaml.safe_load(h).items())

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
    dhcppython.options.TFTPServerName(code=66, length=len(tftpd_addr.encode()), data=tftpd_addr.encode())
  ]

  loop = asyncio.get_running_loop()
  transport_67, protocol = await loop.create_datagram_endpoint(
    lambda: DHCPProxy(boot_tracker, 67, proxy_ip, tftpd_addr, base_option_list, compiled_boot_map),
    sock=sock_67
  )
  transport_4011, protocol = await loop.create_datagram_endpoint(
    lambda: DHCPProxy(boot_tracker, 4011, proxy_ip, tftpd_addr, base_option_list, compiled_boot_map),
    sock=sock_4011
  )
  ready_event.set()
  await shutdown_event.wait()
  log.info('Closing DHCP proxy')
  transport_67.close()
  transport_4011.close()

class DHCPProxy(object):

  boot_tracker: BootTracker
  boot_map: BootMap

  def __init__(self, boot_tracker, port, proxy_ip, tftpd_addr, base_option_list, boot_map: BootMap):
    self.boot_tracker = boot_tracker
    self.port = port
    self.proxy_ip = proxy_ip
    self.tftpd_addr = tftpd_addr
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

      options = message.options.as_dict()

      macaddr: macaddress.MAC = macaddress.parse(message.chaddr, macaddress.MAC)
      if 'PXEClient' not in options.get('vendor_class_identifier', ''):
        log.debug(f'Non-PXE client request received from {macaddr}')
        return

      if options['dhcp_message_type'] == 'DHCPDISCOVER' and self.port == 67:
        response_type = dhcppython.packet.DHCPPacket.Offer
      elif options['dhcp_message_type'] == 'DHCPREQUEST' and self.port == 67:
        requested_ip = options.get('requested_ip_address', None)
        if requested_ip is not None:
          log.debug(f'{macaddr} requested IP {requested_ip}')
          self.boot_tracker.ip_requested(macaddr, ipaddress.ip_address(requested_ip))
        return
      elif options['dhcp_message_type'] == 'DHCPREQUEST' and self.port == 4011:
        response_type = dhcppython.packet.DHCPPacket.Ack
      else:
        log.info(f'Unhandled DHCP message type {options['dhcp_message_type']} from {macaddr} on port {self.port}')
        return

      log.info(f'PXE client {options['dhcp_message_type']} received from {macaddr}')
      option_list = list(self.base_option_list)
      uuid_opt = message.options.by_code(97)
      if uuid_opt is not None:
        option_list.append(uuid_opt)

      match_string = f'{options.get('vendor_class_identifier')}/{options.get('ClientSystem_93', '')}'
      file_path = None
      for matcher, boot_spec in self.boot_map.items():
        if matcher.search(match_string) is not None:
          if boot_spec is not None:
            # No break, last match wins
            file_path = str(self.boot_tracker.get_variant_dir(macaddr, boot_spec['variant']) / boot_spec['filename']).encode()
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
        sname=self.tftpd_addr.encode(),
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
