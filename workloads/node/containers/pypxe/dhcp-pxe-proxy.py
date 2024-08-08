'''dhcp-pxe-proxy.py
Usage:
  dhcp-pxe-proxy.py [options] HOST_IP TFTPD_ADDR

Options:
  -b --boot-map PATH  Path to YAML regex map of "vendor-client/arch" DHCP
                      options to TFTP boot file paths [default: boot-map.yaml]
'''
# Source https://github.com/pypxe/PyPXE/blob/466c8c07d13edea0a6a3bbbb027bfd41456af83a/pypxe/dhcp.py
# The entire DHCP server part has been removed

import socket
import os
import logging
import signal
import time
import yaml
import netifaces
import docopt
import re
import dhcppython
import ipaddress
import select

log = logging.getLogger('dhcp-pxe-proxy.py')
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

TYPE_OF_SVC_ROUTING_CONTROL = 0xc0
OPT_VENDOR_SPEC_INFO = 43
OPT_ADDR_REQ = 50
OPT_MSG_TYPE = 53
MSG_TYPE_DHCPDISCOVER = 1
MSG_TYPE_DHCPOFFER = 2
MSG_TYPE_DHCPREQUEST = 3
MSG_TYPE_DHCPACK = 5
OPT_DHCP_SRV_ID = 54
OPT_VENDOR_CLASS_IDENTIFIER = 60
OPT_SERVER_NAME = 66
OPT_BOOTFILE_NAME = 67
OPT_ARCH = 93
OPT_UUID = 97
PXE_CLIENT_ID='PXEClient'

params = docopt.docopt(__doc__)


############################
### Figure out addresses ###
############################

proxy_ip = ipaddress.ip_address(params['HOST_IP'])
tftpd_addr = ipaddress.ip_address(params['TFTPD_ADDR'])

(iface, af, iface_addr) = next(((iface, af, iface_addr)
  for iface in netifaces.interfaces()
  for af, iface_addrs in netifaces.ifaddresses(iface).items()
  for iface_addr in iface_addrs
  if iface_addr['addr'] == params['HOST_IP']), (None, None, None))

if iface is None:
  raise Exception(f'Unable to find interface for the IP {proxy_ip}')

broadcast = iface_addr['broadcast']
broadcast = '255.255.255.255'

iface_link = netifaces.ifaddresses(iface).get(netifaces.AF_LINK, None)
if iface_link is None or len(iface_link) == 0 or 'addr' not in iface_link[0]:
  raise Exception(f'Unable to determine MAC address for the IP {proxy_ip}')

proxy_mac = iface_link[0]['addr']

gateway_ip = next((gateway_ip for _, gw in filter(lambda i: i[0] != 'default' and i[0] == af, netifaces.gateways().items()) for (gateway_ip, _iface, is_default) in gw if _iface == iface and is_default), None)

if gateway_ip is None:
  raise Exception(f'Unable to determine gateway for the IP {proxy_ip}')

def shutdown(signum, frame):
  raise SystemExit(f'{signal.Signals(signum).name} received, shutting down')
signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

opt_arch_memo = {}
memo_expiry = 60  # Remember client arch from a discover message for a minute
# DHCPPacket(op='BOOTREQUEST', htype='ETHERNET', hlen=6, hops=0, xid=4238412979, secs=0, flags=32768,
#   ciaddr=IPv4Address('0.0.0.0'), yiaddr=IPv4Address('0.0.0.0'), siaddr=IPv4Address('0.0.0.0'), giaddr=IPv4Address('0.0.0.0'), chaddr='00:15:5D:CD:6B:04',
#   sname=b'', file=b'', options=OptionList([
#     MessageType(code=53, length=1, data=b'\x01'),
#     MaxDHCPMessageSize(code=57, length=2, data=b'\x05\xc0'),
#     ParameterRequestList(code=55, length=35, data=b'\x01\x02\x03\x04\x05\x06\x0c\r\x0f\x11\x12\x16\x17\x1c()*+236:;<BCa\x80\x81\x82\x83\x84\x85\x86\x87'),
#     UnknownOption(code=97, length=17, data=b'\x00mQ\xb0r\xfd\xbe\x08G\xa8\xdc$`\x13\x19\xcd8'),
#     UnknownOption(code=94, length=3, data=b'\x01\x03\x00'),
#     UnknownOption(code=93, length=2, data=b'\x00\x07'),
#     VendorClassIdentifier(code=60, length=32, data=b'PXEClient:Arch:00007:UNDI:003000'),
#     End(code=255, length=0, data=b'')
#   ]))
# {'dhcp_message_type': 'DHCPDISCOVER',
# 'max_dhcp_message_size': 1472, 'parameter_request_list': [1, 2, 3, 4, 5, 6, 12, 13, 15, 17, 18, 22, 23, 28, 40, 41, 42, 43, 50, 51, 54, 58, 59, 60, 66, 67, 97, 128, 129, 130, 131, 132, 133, 134, 135],
# 'UUID/GUID_97': '0x00 0x6D 0x51 0xB0 0x72 0xFD 0xBE 0x08 0x47 0xA8 0xDC 0x24 0x60 0x13 0x19 0xCD 0x38',
# 'ClientNDI_94': '0x01 0x03 0x00',
# 'ClientSystem_93': '0x00 0x07',
# 'vendor_class_identifier': 'PXEClient:Arch:00007:UNDI:003000',
# 'end_option': ''}

########################
### Compile boot map ###
########################
with open(params['--boot-map'], 'r') as h:
  boot_map_raw = yaml.safe_load(h)
  boot_map = {}
  for regex, file_path in boot_map_raw.items():
    boot_map[re.compile(regex)] = file_path

def get_file_path(match_string: str):
  file_path = None
  for matcher, _file_path in boot_map.items():
    if matcher.search(match_string) is not None:
      # No break, last match wins
      file_path = _file_path
  return file_path


########################
### Setup UDP socket ###
########################
sockets = {
  67: socket.socket(af, socket.SOCK_DGRAM, socket.IPPROTO_UDP),
  4011: socket.socket(af, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
}
sockets[67].setsockopt(socket.IPPROTO_IP, 10, 0) # Remove the DF (Don't fragment) flag
sockets[67].setsockopt(socket.IPPROTO_IP, socket.IP_TOS, TYPE_OF_SVC_ROUTING_CONTROL)
sockets[67].setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sockets[67].setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sockets[67].bind(('', 67 ))
sockets[4011].setsockopt(socket.IPPROTO_IP, 10, 0) # Remove the DF (Don't fragment) flag
sockets[4011].setsockopt(socket.IPPROTO_IP, socket.IP_TOS, TYPE_OF_SVC_ROUTING_CONTROL)
sockets[4011].setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sockets[4011].bind(('', 4011 ))

base_option_list = [
  dhcppython.options.ServerIdentifier(code=OPT_DHCP_SRV_ID, length=len(proxy_ip.packed), data=proxy_ip.packed),
  dhcppython.options.VendorClassIdentifier(code=OPT_VENDOR_CLASS_IDENTIFIER, length=len(PXE_CLIENT_ID.encode()), data=PXE_CLIENT_ID.encode())
]
log.info('Startup completed')
try:
  while True:
    try:
      readable, writable, exceptional = select.select(sockets.values(), [], sockets.values())
      for sock in readable:
        raw_message, address = sock.recvfrom(1024)
        print(address)
        # time.sleep(0.001)
        now = time.time()
        for mac, memo in list(opt_arch_memo.items()):
          if now - memo['time'] > memo_expiry:
            del opt_arch_memo[mac]
        message = dhcppython.packet.DHCPPacket.from_bytes(raw_message)
        log.debug(f'Received message: {message}')
        options = message.options.as_dict()
        # client request is valid only if contains Vendor-Class = PXEClient
        if PXE_CLIENT_ID not in options.get('vendor_class_identifier', ''):
          log.debug(f'Non-PXE client request received from {message.chaddr}')
          continue

        response: dhcppython.packet
        if options['dhcp_message_type'] not in ['DHCPDISCOVER', 'DHCPREQUEST']:
          log.debug(f'Unhandled DHCP message type {options['dhcp_message_type']} from {message.chaddr}')
          continue

        log.info(f'PXE client {options['dhcp_message_type']} received from {message.chaddr}')

        uuid_opt = message.options.by_code(OPT_UUID)
        option_list = list(base_option_list)
        if uuid_opt is not None:
          option_list.append(uuid_opt)

        if options['dhcp_message_type'] == 'DHCPDISCOVER' and sock == sockets[67]:
          if 'ClientSystem_93' in options:
            opt_arch_val = options['ClientSystem_93']
            opt_arch_memo[message.chaddr] = { 'time': now, 'value': options['ClientSystem_93'] }
          match_string = f'{options.get('vendor_class_identifier')}/{opt_arch_val}'
          file_path = get_file_path(match_string)
          if file_path is None:
            log.info(f'No match found in {params["--boot-map"]} for {match_string}')
            continue
          tftpd_addr_b = params['TFTPD_ADDR'].encode()
          file_path_b = file_path.encode()
          option_list.append(dhcppython.options.TFTPServerName(code=OPT_SERVER_NAME, length=len(tftpd_addr_b), data=tftpd_addr_b))
          option_list.append(dhcppython.options.BootfileName(code=OPT_BOOTFILE_NAME, length=len(file_path_b), data=file_path_b))
          response = dhcppython.packet.DHCPPacket.Offer(
            message.chaddr,
            seconds=0,
            tx_id=message.xid,
            yiaddr='0.0.0.0',
            sname=''.encode(),
            # sname=params['TFTPD_ADDR'].encode(),
            fname=file_path.encode(),
            option_list=option_list
          )
          response.siaddr = proxy_ip
          dest = (broadcast, 68)
          log.debug(f'Responding with {response}')
          sock.sendto(response.asbytes + b'\x00' * 20, dest)
        elif options['dhcp_message_type'] == 'DHCPREQUEST' and sock == sockets[4011]:
          # DHCPPacket(op='BOOTREPLY', htype='ETHERNET', hlen=6, hops=0, xid=1589818651, secs=0, flags=0,
          # ciaddr=IPv4Address('10.192.205.224'), yiaddr=IPv4Address('0.0.0.0'), siaddr=IPv4Address('10.192.205.226'), giaddr=IPv4Address('0.0.0.0'), chaddr='00:15:5D:CD:6B:04',
          # sname=b'', file=b'images/amd64/uki.efi', options=OptionList([
          # MessageType(code=53, length=1, data=b'\x05'),
          # ServerIdentifier(code=54, length=4, data=b'\n\xc0\xcd\xe2'),
          # VendorClassIdentifier(code=60, length=9, data=b'PXEClient'),
          # UnknownOption(code=97, length=17, data=b'\x00mQ\xb0r\xfd\xbe\x08G\xa8\xdc$`\x13\x19\xcd8'),
          # VendorSpecificInformation(code=43, length=10, data=b'\x06\x01\x08\n\x04\x00PXE\xff'),
          # End(code=255, length=0, data=b'')]))
          opt_arch_val = options.get('ClientSystem_93', opt_arch_memo.get(message.chaddr, {'value': None})['value'])
          match_string = f'{options.get('vendor_class_identifier')}/{opt_arch_val}'
          file_path = get_file_path(match_string)
          if file_path is None:
            log.info(f'No match found in {params["--boot-map"]} for {match_string}')
            continue
          # vendor = b'0601080a0400505845ff'
          response = dhcppython.packet.DHCPPacket.Ack(
            message.chaddr,
            seconds=0,
            tx_id=message.xid,
            yiaddr='0.0.0.0',
            sname=''.encode(),
            # sname=params['TFTPD_ADDR'].encode(),
            fname=file_path.encode(),
            option_list=option_list
          )
          ciaddr=''
          response.siaddr = proxy_ip
          log.debug(f'Responding with {response}')
          sock.sendto(response.asbytes + b'\x00' * 20, (str(message.ciaddr), 4011))

    except Exception as e:
      raise e
      log.error(e)
finally:
  for sock in sockets.values():
    sock.close()

# def craft_header(message, tftpd_addr, file_path):
#   '''This method crafts the DHCP header using parts of the message.'''
#   xid, flags, yiaddr, giaddr, chaddr = struct.unpack('!4x4s2x2s4x4s4x4s16s', message[:44])

#   # op, htype, hlen, hops, xid
#   response =  struct.pack('!BBBB4s', 2, 1, 6, 0, xid)
#   response += struct.pack('!HHI', 0, 0x8000, 0)
#   response += socket.inet_aton('0.0.0.0')
#   response += socket.inet_aton('0.0.0.0')
#   response += socket.inet_aton(tftpd_addr) # siaddr
#   # response += socket.inet_aton('0.0.0.0') # giaddr
#   response += chaddr # chaddr

#   # BOOTP legacy pad
#   response += b'\x00' * 64 # server name
#   response += file_path.encode('ascii')
#   response += b'\x00' * (128 - len(file_path))
#   response += struct.pack('!I', 0x63825363) # magic cookie/section
#   return response

# def craft_options(proxy_ip, options, tftpd_addr, file_path):
#   '''
#     This method crafts the DHCP option fields
#     opt53:
#       2 - DHCPOFFER
#       5 - DHCPACK
#     See RFC2132 9.6 for details.
#   '''
#   msg_type_req = ord(options[OPT_MSG_TYPE][0])

#   if msg_type_req == MSG_TYPE_DHCPDISCOVER:
#     msg_type_resp = MSG_TYPE_DHCPOFFER
#   elif msg_type_req == MSG_TYPE_DHCPREQUEST:
#     msg_type_resp = MSG_TYPE_DHCPACK
#   response = tlv_encode(OPT_MSG_TYPE, struct.pack('!B', msg_type_resp))
#   response += tlv_encode(OPT_DHCP_SRV_ID, socket.inet_aton(proxy_ip)) # DHCP Server

#   # response += tlv_encode(OPT_SERVER_NAME, tftpd_addr)

#   # response += tlv_encode(OPT_BOOTFILE_NAME, file_path.encode('ascii') + b'\x00')
#   response += tlv_encode(OPT_VENDOR_CLIENT, 'PXEClient')
#   if OPT_UUID in options:
#     response += tlv_encode(OPT_UUID, options[OPT_UUID][0])
#   # response += struct.pack('!BBBBBBB4sB', 43, 10, 6, 1, 0b1000, 10, 4, b'\x00' + b'PXE', 0xff)
#   response += b'\xff'
#   response += b'\x00' * 20
#   return response
