import asyncio, socket, logging
import ipaddress, dhcppython
from . import AnyIPAddress, Context
from .boot_events import node_crashed_on_bootup, pxe_request_received, boot_server_discovery_request_received
import macaddress
from .node import Node
from .image import Image

log = logging.getLogger(__name__)

async def dhcp_proxy(ctx: Context, ready_event: asyncio.Event):
  log.info('Starting DHCP proxy')
  proxy_ip = ctx.host_ip
  tftpd_ip = ctx.host_ip

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
    lambda: DHCPProxy(ctx, 67, proxy_ip, tftpd_ip, base_option_list),
    sock=sock_67
  )
  transport_4011, protocol = await loop.create_datagram_endpoint(
    lambda: DHCPProxy(ctx, 4011, proxy_ip, tftpd_ip, base_option_list),
    sock=sock_4011
  )
  ready_event.set()
  await ctx.shutdown_event.wait()
  log.info('Closing DHCP proxy')
  transport_67.close()
  transport_4011.close()

class DHCPProxy(asyncio.DatagramProtocol):

  ctx: Context
  port: int
  proxy_ip: ipaddress.IPv4Address
  tftpd_ip: AnyIPAddress
  base_option_list: list[dhcppython.options.Option]

  def __init__(self, ctx: Context, port: int,
               proxy_ip: ipaddress.IPv4Address, tftpd_ip: AnyIPAddress,
               base_option_list: list[dhcppython.options.Option]):
    self.ctx = ctx
    self.port = port
    self.proxy_ip = proxy_ip
    self.tftpd_ip = tftpd_ip
    self.base_option_list = base_option_list

  def connection_made(self, transport):
    self.transport = transport

  def connection_lost(self, exc):
    if exc is not None:
      log.exception(exc)

  def datagram_received(self, data, addr):
    try:
      (client_ip, client_port) = addr
      message = dhcppython.packet.DHCPPacket.from_bytes(data)
      log.debug(f'Received message: {message}')

      def get_opt(code: int, default=None) -> str | None:
        opt = message.options.by_code(code)
        return default if opt is None or opt.value is None else opt.value[opt.key]

      macaddr: macaddress.MAC = macaddress.parse(message.chaddr, macaddress.MAC)
      vendor_class_identifier = get_opt(dhcppython.options.VendorClassIdentifier.code, '')
      if vendor_class_identifier is None or 'PXEClient' not in vendor_class_identifier:
        log.debug(f'Non-PXE client request received from {macaddr}')
        return

      node = Node.get_by_mac(self.ctx, macaddr) or Node.new_by_mac(self.ctx, macaddr)

      dhcp_message_type = get_opt(dhcppython.options.MessageType.code)
      if dhcp_message_type == 'DHCPDISCOVER' and self.port == 67:
        response_type = dhcppython.packet.DHCPPacket.Offer
      elif dhcp_message_type == 'DHCPREQUEST' and self.port == 67:
        requested_ip = get_opt(dhcppython.options.RequestedIPAddress.code)
        if requested_ip is not None:
          log.debug(f'{node} requested IP {requested_ip}')
        return
      elif dhcp_message_type == 'DHCPREQUEST' and self.port == 4011:
        response_type = dhcppython.packet.DHCPPacket.Ack
      else:
        log.info(f'Unhandled DHCP message type {dhcp_message_type} from {macaddr} on port {self.port}')
        return

      option_list = list(self.base_option_list)
      uuid_opt = message.options.by_code(97)
      if uuid_opt is not None:
        option_list.append(uuid_opt)

      fname=b""
      if vendor_class_identifier == 'PXEClient:home-cluster':
        boot_server_discovery_request_received(self.ctx, node)
      else:
        pxe_request_received(self.ctx, node)
        if node.variant is None:
          client_system = get_opt(93, '')
          match_string = f'{vendor_class_identifier}/{client_system}'
          matches = [
            variant for matcher, variant in reversed(self.ctx.variant_map.items())
            if matcher.search(match_string) is not None
          ]
          variant = matches[-1] if len(matches) > 1 else None
          if variant is None:
            log.error(f"No match found in variant-map for '{match_string}'")
            return
          else:
            node.variant = variant

        if node.booting_image is not None:
          node_crashed_on_bootup(self.ctx, node)
          node.booting_image.boot_results.log_failure(node)

        if node.bootnext_image is not None:
          image = node.bootnext_image
          del node.bootnext_image
        else:
          if node.stable_image is None:
            image = Image.get_stable(self.ctx, node.variant)
          else:
            image = node.stable_image
        if image is None:
          log.error(f"Unable to find any image for variant '{node.variant}'")
          return
        node.booting_image = image

        # Use the node ID as the boot filename. This way we can track the boot process without having to map mac to IP to machine-id
        boot_filename = str(node.id).encode()
        option_list.append(dhcppython.options.BootfileName(code=67, length=len(boot_filename), data=boot_filename))
        fname = boot_filename

      response = response_type(
        message.chaddr,
        seconds=0,
        tx_id=message.xid,
        yiaddr='0.0.0.0',
        sname=str(self.tftpd_ip).encode(),
        fname=fname,
        option_list=option_list
      )
      response.siaddr = self.proxy_ip
      log.debug(f'Responding with {response}')
      self.transport.sendto(response.asbytes, ('255.255.255.255' if client_ip == '0.0.0.0' else client_ip, client_port))
    except SystemExit as e:
      return
    except Exception as e:
      log.exception(e)
