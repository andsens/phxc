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
import struct
import os
import logging
import sys
import signal
import time
import yaml
import netifaces
import docopt
import re

log = logging.getLogger('dhcp-pxe-proxy.py')
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

TYPE_53_DHCPDISCOVER = 1
TYPE_53_DHCPREQUEST = 3

def main():
  params = docopt.docopt(__doc__)

  proxy_ip = params['HOST_IP']

  with open(params['--boot-map'], 'r') as h:
    boot_map_raw = yaml.safe_load(h)
    boot_map = {}
    for regex, file_path in boot_map_raw.items():
      boot_map[re.compile(regex)] = file_path

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

  opt93_memo = {}
  memo_expiry = 60  # Remember client arch from a discover message for a minute

  log.info('Startup completed')
  try:
    while True:
      message, address = sock.recvfrom(1024)
      # try:
      now = time.time()
      for mac, memo in list(opt93_memo.items()):
        if now - memo['time'] > memo_expiry:
          del opt93_memo[mac]
      [raw_client_mac] = struct.unpack('!28x6s', message[:34])
      client_mac = ':'.join(map(lambda x: hex(x)[2:].zfill(2), struct.unpack('BBBBBB', raw_client_mac))).upper()
      log.debug(f'Received message: {repr(message)}')
      options = tlv_parse(message[240:])
      log.debug(f'Parsed received options: {repr(options)}')
      # client request is valid only if contains Vendor-Class = PXEClient
      if 60 not in options or 'PXEClient'.encode() not in options[60][0]:
        log.debug(f'Non-PXE client request received from {client_mac}')
        continue

      log.info(f'PXE client request received from {client_mac}')

      msg_type = ord(options[53][0]) # see RFC2131, page 10
      if msg_type not in [TYPE_53_DHCPDISCOVER, TYPE_53_DHCPREQUEST]:
        log.debug(f'Unhandled DHCP message type {msg_type} from {client_mac}')
        continue
      if msg_type == TYPE_53_DHCPDISCOVER:
        response_type = { 'name': 'DHCPOFFER', 'opt53': 2 }
        opt93 = options.get(93, None)
        opt93_memo[raw_client_mac] = { 'time': now, 'value': opt93 }
      elif msg_type == TYPE_53_DHCPREQUEST:
        response_type = { 'name': 'DHCPACK', 'opt53': 5 }
        opt93 = options.get(93, opt93_memo.get(raw_client_mac, {'value': None})['value'])

      vendor_client = options[60][0].decode('ascii')
      arch = '' if opt93 is None else f'0x{struct.unpack('!H', opt93[0])[0]:02x}'
      match_string = f'{vendor_client}/{arch}'
      file_path = None
      for matcher, _file_path in boot_map.items():
        if matcher.search(match_string) is not None:
          # No break, last match wins
          file_path = _file_path

      if file_path is None:
        log.info(f'No match found in {params["--boot-map"]} for {match_string}, not sending {response_type['name']}')

      header_response = craft_header(message, tftpd_addr, file_path)
      options_response = craft_options(proxy_ip, response_type['opt53'], tftpd_addr, file_path)
      log.debug(f'''Sending {response_type['name']} with file path {file_path} to {client_mac}
Header: {repr(header_response)}
Options: {repr(options_response)}''')
      sock.sendto(header_response + options_response, (broadcast, 68))
      # except Exception as e:
      #   log.error(e)
  finally:
    sock.close()

def craft_header(message, tftpd_addr, file_path):
  '''This method crafts the DHCP header using parts of the message.'''
  xid, flags, yiaddr, giaddr, chaddr = struct.unpack('!4x4s2x2s4x4s4x4s16s', message[:44])

  # op, htype, hlen, hops, xid
  response =  struct.pack('!BBBB4s', 2, 1, 6, 0, xid)
  response += struct.pack('!HHI', 0, 0x8000, 0)
  response += socket.inet_aton('0.0.0.0')
  response += socket.inet_aton(tftpd_addr) # siaddr
  response += socket.inet_aton('0.0.0.0') # giaddr
  response += chaddr # chaddr

  # BOOTP legacy pad
  response += b'\x00' * 64 # server name
  response += file_path.encode('ascii')
  response += b'\x00' * (128 - len(file_path))
  response += struct.pack('!I', 0x63825363) # magic cookie/section
  return response

def craft_options(proxy_ip, opt53, tftpd_addr, file_path):
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

  response += tlv_encode(67, file_path.encode('ascii') + b'\x00')
  response += tlv_encode(60, 'PXEClient')
  response += struct.pack('!BBBBBBB4sB', 43, 10, 6, 1, 0b1000, 10, 4, b'\x00' + b'PXE', 0xff)
  response += b'\xff'
  return response

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
