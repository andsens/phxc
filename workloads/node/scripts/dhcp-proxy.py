'''dhcp-proxy.py
Usage:
  dhcp-proxy.py [options] HOST_IP TFTPD_ADDR

Options:
  -b --boot-map PATH  Path to YAML regex map of "vendor-client/arch" DHCP
                      options to TFTP boot file paths [default: boot-map.yaml]
  -u --user NAME      Drop privileges after binding sockets and run as
                      specified user [default: nobody]
'''

import socket
import os
import logging
import signal
import re
import ipaddress
import select
import yaml
import docopt
import dhcppython
import pwd

log = logging.getLogger('dhcp-proxy.py')
log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)


params = docopt.docopt(__doc__)

proxy_ip = ipaddress.ip_address(params['HOST_IP'])
tftpd_addr = params['TFTPD_ADDR'].encode()

def shutdown(signum, frame):
  raise SystemExit(f'{signal.Signals(signum).name} received, shutting down')
signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

########################
### Compile boot map ###
########################
with open(params['--boot-map'], 'r') as h:
  boot_map = dict((re.compile(regex), file_path) for regex, file_path in yaml.safe_load(h).items())

def get_file_path(match_string: str):
  file_path = None
  for matcher, _file_path in boot_map.items():
    if matcher.search(match_string) is not None:
      # No break, last match wins
      file_path = _file_path
  return None if file_path is None else file_path.encode()

#########################
### Setup UDP sockets ###
#########################
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

user_uid = pwd.getpwnam(params['--user']).pw_uid
log.debug(f'Sockets bound, dropping to user {params['--user']} (UID: {user_uid})')
os.setuid(user_uid)

base_option_list = [
  dhcppython.options.ServerIdentifier(code=54, length=len(proxy_ip.packed), data=proxy_ip.packed),
  dhcppython.options.VendorClassIdentifier(code=60, length=len('PXEClient'.encode()), data='PXEClient'.encode()),
  dhcppython.options.TFTPServerName(code=66, length=len(tftpd_addr), data=tftpd_addr)
]
log.info('Startup completed')
try:
  while True:
    try:
      readable, writable, exceptional = select.select([sock_67, sock_4011], [], [sock_67, sock_4011])
      for sock in readable:
        raw_message, (client_ip, client_port) = sock.recvfrom(1024)

        message = dhcppython.packet.DHCPPacket.from_bytes(raw_message)

        log.debug(f'Received message: {message}')
        options = message.options.as_dict()

        if 'PXEClient' not in options.get('vendor_class_identifier', ''):
          log.debug(f'Non-PXE client request received from {message.chaddr}')
          continue

        if options['dhcp_message_type'] == 'DHCPDISCOVER' and sock == sock_67:
          response_type = dhcppython.packet.DHCPPacket.Offer
        elif options['dhcp_message_type'] == 'DHCPREQUEST' and sock == sock_4011:
          response_type = dhcppython.packet.DHCPPacket.Ack
        else:
          log.debug(f'Unhandled DHCP message type {options['dhcp_message_type']} from {message.chaddr} on port {67 if sock == sock_67 else 4011}')
          continue

        log.info(f'PXE client {options['dhcp_message_type']} received from {message.chaddr}')
        option_list = list(base_option_list)
        uuid_opt = message.options.by_code(97)
        if uuid_opt is not None:
          option_list.append(uuid_opt)

        match_string = f'{options.get('vendor_class_identifier')}/{options.get('ClientSystem_93', '')}'
        file_path = get_file_path(match_string)
        if file_path is None:
          log.info(f"No match found in {params['--boot-map']} for '{match_string}'")
          continue
        option_list.append(dhcppython.options.BootfileName(code=67, length=len(file_path), data=file_path))

        response = response_type(
          message.chaddr,
          seconds=0,
          tx_id=message.xid,
          yiaddr='0.0.0.0',
          sname=tftpd_addr,
          fname=file_path,
          option_list=option_list
        )
        response.siaddr = proxy_ip
        log.debug(f'Responding with {response}')
        sock.sendto(response.asbytes, ('255.255.255.255' if client_ip == '0.0.0.0' else client_ip, client_port))

    except Exception as e:
      log.error(e)
finally:
  sock_67.close()
  sock_4011.close()
