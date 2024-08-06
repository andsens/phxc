'''dhcp-pxe-proxy.py
Usage:
  dhcp-pxe-proxy.py HOST_IP TFTPD_ADDR
'''
# Source https://github.com/pypxe/PyPXE/blob/466c8c07d13edea0a6a3bbbb027bfd41456af83a/pypxe/dhcp.py
# The entire DHCP server part has been removed

import socket
import struct
import os
import logging
import sys
import signal
import netifaces
import docopt

log = logging.getLogger('dhcp-pxe-proxy.py')
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

TYPE_53_DHCPDISCOVER = 1
TYPE_53_DHCPREQUEST = 3
response_type_map = {
  TYPE_53_DHCPDISCOVER: {
    'name': 'DHCPOFFER',
    'opt53': 2
  },
  TYPE_53_DHCPREQUEST: {
    'name': 'DHCPACK',
    'opt53': 5
  }
}

def main():
  params = docopt.docopt(__doc__)
  proxy_ip = params['HOST_IP']
  broadcast = None
  for ifaces in netifaces.interfaces():
    for iface_addrs in netifaces.ifaddresses(ifaces).values():
      for iface_addr in iface_addrs:
        if iface_addr['addr'] == proxy_ip:
          # calculate the broadcast address from ip and subnet_mask
          nip = struct.unpack('!I', socket.inet_aton(proxy_ip))[0]
          nmask = struct.unpack('!I', socket.inet_aton(iface_addr['netmask']))[0]
          nbroadcast = (nip & nmask) | ((~ nmask) & 0xffffffff)
          broadcast = socket.inet_ntoa(struct.pack('!I', nbroadcast))

  if broadcast is None:
    raise Exception(f'Unable to find interface for the IP {proxy_ip}')

  tftpd_addr = params['TFTPD_ADDR']
  file_name = 'pxelinux.0'

  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
  sock.bind(('', 67 ))

  def shutdown(signum, frame):
    raise SystemExit(f'{signal.Signals(signum).name} received, shutting down')
  signal.signal(signal.SIGTERM, shutdown)
  signal.signal(signal.SIGINT, shutdown)

  log.info('Startup completed')
  try:
    while True:
      message, address = sock.recvfrom(1024)
      [client_mac] = struct.unpack('!28x6s', message[:34])
      log.debug(f'Received message: {repr(message)}')
      options = tlv_parse(message[240:])
      log.debug(f'Parsed received options: {repr(options)}')
      # client request is valid only if contains Vendor-Class = PXEClient
      if 60 not in options or 'PXEClient'.encode() not in options[60][0]:
        log.info(f'Non-PXE client request received from {get_mac(client_mac)}')
        continue
      log.info(f'PXE client request received from {get_mac(client_mac)}')
    # http://www.syslinux.org/wiki/index.php/PXELINUX#UEFI
    # if 'options' in self.leases[client_mac] and 93 in self.leases[client_mac]['options']:
    #   [arch] = struct.unpack("!H", self.leases[client_mac]['options'][93][0])
    #   file_name = {0: 'pxelinux.0', # BIOS/default
    #         6: 'syslinux.efi32', # EFI IA32
    #         7: 'syslinux.efi64', # EFI BC, x86-64
    #         9: 'syslinux.efi64'  # EFI x86-64
    #         }[arch]

      msg_type = ord(options[53][0]) # see RFC2131, page 10
      response_type = response_type_map.get(msg_type, None)
      if response_type is None:
        log.debug(f'Unhandled DHCP message type {msg_type} from {get_mac(client_mac)}')
        continue

      client_mac, header_response = craft_header(message, tftpd_addr, file_name)
      options_response = craft_options(proxy_ip, response_type['opt53'], tftpd_addr, file_name)
      log.debug(f'''Sending {response_type['name']} to {get_mac(client_mac)}:
  <--HEADER-->
  {repr(header_response)}
  <--OPTIONS-->
  {repr(options_response)}
  ''')
      sock.sendto(header_response + options_response, (broadcast, 68))
  finally:
    sock.close()

def craft_header(message, tftpd_addr, file_name):
  '''This method crafts the DHCP header using parts of the message.'''
  xid, flags, yiaddr, giaddr, chaddr = struct.unpack('!4x4s2x2s4x4s4x4s16s', message[:44])
  client_mac = chaddr[:6]

  # op, htype, hlen, hops, xid
  response =  struct.pack('!BBBB4s', 2, 1, 6, 0, xid)
  response += struct.pack('!HHI', 0, 0x8000, 0)
  response += socket.inet_aton('0.0.0.0')
  response += socket.inet_aton(tftpd_addr) # siaddr
  response += socket.inet_aton('0.0.0.0') # giaddr
  response += chaddr # chaddr

  # BOOTP legacy pad
  response += b'\x00' * 64 # server name
  response += file_name.encode('ascii')
  response += b'\x00' * (128 - len(file_name))
  response += struct.pack('!I', 0x63825363) # magic cookie/section
  return (client_mac, response)

def craft_options(proxy_ip, opt53, tftpd_addr, file_name):
  '''
    This method crafts the DHCP option fields
    opt53:
      2 - DHCPOFFER
      5 - DHCPACK
    See RFC2132 9.6 for details.
  '''
  response = tlv_encode(53, struct.pack('!B', opt53))
  response += tlv_encode(54, socket.inet_aton(proxy_ip)) # DHCP Server

  response += tlv_encode(66, tftpd_addr)

  response += tlv_encode(67, file_name.encode('ascii') + b'\x00')
  response += tlv_encode(60, 'PXEClient')
  response += struct.pack('!BBBBBBB4sB', 43, 10, 6, 1, 0b1000, 10, 4, b'\x00' + b'PXE', 0xff)
  response += b'\xff'
  return response

def get_mac(mac):
  '''
    This method converts the MAC Address from binary to
    human-readable format for logging.
  '''
  return ':'.join(map(lambda x: hex(x)[2:].zfill(2), struct.unpack('BBBBBB', mac))).upper()

def tlv_encode(tag, value):
  '''Encode a TLV option.'''
  if type(value) is str:
    value = value.encode('ascii')
  value = bytes(value)
  return struct.pack('BB', tag, len(value)) + value

def tlv_parse(raw):
  '''Parse a string of TLV-encoded options.'''
  ret = {}
  while(raw):
    [tag] = struct.unpack('B', raw[0:1])
    if tag == 0: # padding
      raw = raw[1:]
      continue
    if tag == 255: # end marker
      break
    [length] = struct.unpack('B', raw[1:2])
    value = raw[2:2 + length]
    raw = raw[2 + length:]
    if tag in ret:
      ret[tag].append(value)
    else:
      ret[tag] = [value]
  return ret

if __name__ == '__main__':
  main()
