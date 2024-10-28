import asyncio, socket, logging
import ipaddress, dhcppython
from . import AnyIPAddress
from .context import Context
from .bootmanager import get_boot_spec, get_image_dir
import macaddress
from .node import Node

log = logging.getLogger(__name__)

async def dhcp_proxy(ready_event: asyncio.Event, context: Context):
  log.info('Starting DHCP proxy')
  proxy_ip = context['config']['host_ip']
  tftpd_ip = context['config']['host_ip']

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
    lambda: DHCPProxy(context, 67, proxy_ip, tftpd_ip, base_option_list),
    sock=sock_67
  )
  transport_4011, protocol = await loop.create_datagram_endpoint(
    lambda: DHCPProxy(context, 4011, proxy_ip, tftpd_ip, base_option_list),
    sock=sock_4011
  )
  ready_event.set()
  await context['shutdown_event'].wait()
  log.info('Closing DHCP proxy')
  transport_67.close()
  transport_4011.close()

class DHCPProxy(object):

  context: Context
  port: int
  proxy_ip: AnyIPAddress
  tftpd_ip: AnyIPAddress
  base_option_list: list[dhcppython.options.Option]

  def __init__(self, context: Context, port: int,
               proxy_ip: AnyIPAddress, tftpd_ip: AnyIPAddress,
               base_option_list: list[dhcppython.options.Option]):
    self.context = context
    self.port = port
    self.proxy_ip = proxy_ip
    self.tftpd_ip = tftpd_ip
    self.base_option_list = base_option_list

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
          Node.ip_requested(self.context, macaddr, ipaddress.ip_address(requested_ip))
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

      file_path = ''
      # Make sure it isn't a discovery request ("find-boot-server")
      if vendor_class_identifier != 'PXEClient:home-cluster':
        client_system = get_opt(93, '')
        match_string = f'{vendor_class_identifier}/{client_system}'
        boot_spec = get_boot_spec(self.context, match_string)
        if boot_spec is None:
          log.info(f"No match found in boot-map for '{match_string}'")
          return
        image_dir = get_image_dir(self.context, macaddr, boot_spec)
        file_path = image_dir / boot_spec['filename']
        option_list.append(dhcppython.options.BootfileName(code=67, length=len(file_path), data=file_path))

      response = response_type(
        message.chaddr,
        seconds=0,
        tx_id=message.xid,
        yiaddr='0.0.0.0',
        sname=str(self.tftpd_ip).encode(),
        fname=str(file_path).encode(),
        option_list=option_list
      )
      response.siaddr = self.proxy_ip
      log.debug(f'Responding with {response}')
      self.transport.sendto(response.asbytes, ('255.255.255.255' if client_ip == '0.0.0.0' else client_ip, client_port))
    except SystemExit as e:
      return
    except Exception as e:
      log.exception(e)
